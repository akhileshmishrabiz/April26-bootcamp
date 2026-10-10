import os
import json
import logging
import threading
import time
from flask import Flask, jsonify, request, g
from flask_cors import CORS
from prometheus_flask_exporter import PrometheusMetrics
from prometheus_client import Counter, Histogram, Gauge
from dotenv import load_dotenv
from pythonjsonlogger import jsonlogger
import pika
import boto3
from botocore.exceptions import ClientError
from email_templates import render_order_confirmation

load_dotenv()

log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
log_handler = logging.StreamHandler()
log_handler.setFormatter(jsonlogger.JsonFormatter(
    '%(asctime)s %(levelname)s %(name)s %(message)s',
    datefmt='%Y-%m-%dT%H:%M:%SZ',
    rename_fields={'asctime': 'time', 'levelname': 'level'},
    static_fields={'service': 'notification-service'},
))
logging.basicConfig(level=log_level, handlers=[log_handler], force=True)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
metrics = PrometheusMetrics(app)
metrics.info('notification_service_info', 'Notification Service Information', version='1.0.0')

service_http_requests_total = Counter(
    'service_http_requests_total',
    'Total number of HTTP requests',
    ['service', 'method', 'route', 'status_code']
)
service_http_request_duration = Histogram(
    'service_http_request_duration_seconds',
    'Duration of HTTP requests in seconds',
    ['service', 'method', 'route', 'status_code'],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
)
service_http_requests_in_flight = Gauge(
    'service_http_requests_in_flight',
    'Number of HTTP requests currently being served',
    ['service']
)
notification_events_total = Counter(
    'notification_events_total',
    'Total number of notification events consumed',
    ['event_type', 'status']
)
notification_emails_total = Counter(
    'notification_emails_total',
    'Total number of notification emails attempted',
    ['status']
)

@app.before_request
def start_request_metrics():
    if request.path != '/metrics':
        g.metrics_started_at = time.perf_counter()
        service_http_requests_in_flight.labels('notification-service').inc()

@app.after_request
def record_request_metrics(response):
    started_at = getattr(g, 'metrics_started_at', None)
    if started_at is not None:
        route = request.url_rule.rule if request.url_rule else 'unmatched'
        labels = ('notification-service', request.method, route, str(response.status_code))
        service_http_requests_total.labels(*labels).inc()
        service_http_request_duration.labels(*labels).observe(time.perf_counter() - started_at)
        service_http_requests_in_flight.labels('notification-service').dec()
    return response

# AWS SES client
ses_client = boto3.client(
    'ses',
    region_name=os.getenv('AWS_REGION', 'us-east-1'),
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY')
)

SENDER_EMAIL = os.getenv('SES_SENDER_EMAIL', 'noreply@example.com')
SENDER_NAME = os.getenv('SES_SENDER_NAME', 'E-Commerce Platform')

def send_email(to_email, subject, html_body, text_body=None):
    """Send email using AWS SES"""
    try:
        if text_body is None:
            text_body = html_body

        response = ses_client.send_email(
            Source=f'{SENDER_NAME} <{SENDER_EMAIL}>',
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                'Body': {
                    'Text': {'Data': text_body, 'Charset': 'UTF-8'},
                    'Html': {'Data': html_body, 'Charset': 'UTF-8'}
                }
            }
        )
        logger.info(f'Email sent to {to_email}, Message ID: {response["MessageId"]}')
        notification_emails_total.labels('success').inc()
        return True
    except ClientError as e:
        logger.error(f'Failed to send email to {to_email}: {e.response["Error"]["Message"]}')
        notification_emails_total.labels('failed').inc()
        return False
    except Exception as e:
        logger.error(f'Unexpected error sending email: {str(e)}')
        notification_emails_total.labels('failed').inc()
        return False

def process_order_event(event_data):
    """Process order created event and send confirmation email"""
    try:
        event_type = event_data.get('event_type')
        logger.info(f'Processing event: {event_type}')

        if event_type == 'order_created':
            user_email = event_data.get('user_email')
            order_id = event_data.get('order_id')
            total_amount = event_data.get('total_amount')
            items = event_data.get('items', [])

            # Render email template
            html_body = render_order_confirmation(order_id, total_amount, items)
            subject = f'Order Confirmation - {order_id}'

            # Send email
            send_email(user_email, subject, html_body)
            logger.info(f'Order confirmation sent to {user_email}')
            notification_events_total.labels(event_type, 'processed').inc()
        else:
            notification_events_total.labels(event_type or 'unknown', 'ignored').inc()

    except Exception as e:
        logger.error(f'Failed to process order event: {str(e)}')
        notification_events_total.labels(
            event_data.get('event_type', 'unknown'), 'failed'
        ).inc()

def rabbitmq_consumer():
    """RabbitMQ consumer that listens for order events"""
    try:
        connection_params = pika.ConnectionParameters(
            host=os.getenv('RABBITMQ_HOST', 'localhost'),
            port=int(os.getenv('RABBITMQ_PORT', 5672)),
            credentials=pika.PlainCredentials(
                os.getenv('RABBITMQ_USER', 'guest'),
                os.getenv('RABBITMQ_PASSWORD', 'guest')
            ),
            heartbeat=600,
            blocked_connection_timeout=300
        )

        connection = pika.BlockingConnection(connection_params)
        channel = connection.channel()

        # Declare exchange and queue
        channel.exchange_declare(exchange='order_events', exchange_type='topic', durable=True)
        channel.queue_declare(queue='notification_queue', durable=True)
        channel.queue_bind(exchange='order_events', queue='notification_queue', routing_key='order.created')

        def callback(ch, method, properties, body):
            try:
                event_data = json.loads(body)
                logger.info(f'Received message: {event_data.get("event_type")}')
                process_order_event(event_data)
                ch.basic_ack(delivery_tag=method.delivery_tag)
            except Exception as e:
                logger.error(f'Failed to process message: {str(e)}')
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

        channel.basic_consume(queue='notification_queue', on_message_callback=callback)

        logger.info('Waiting for messages. To exit press CTRL+C')
        channel.start_consuming()

    except Exception as e:
        logger.error(f'RabbitMQ consumer error: {str(e)}')

# Start RabbitMQ consumer in a separate thread
consumer_thread = threading.Thread(target=rabbitmq_consumer, daemon=True)
consumer_thread.start()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'notification-service',
        'rabbitmq': 'connected'
    }), 200

if __name__ == '__main__':
    port = int(os.getenv('PORT', 8006))
    logger.info(f'Notification Service starting on port {port}')
    app.run(host='0.0.0.0', port=port, debug=False)
