from prometheus_client import Counter, Histogram, Info, Gauge
import time

# HTTP Metrics
http_requests_total = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)

request_duration_seconds = Histogram(
    "request_duration_seconds", "HTTP request duration in seconds", ["endpoint"]
)

# Student Metrics
student_attendance_marked = Counter(
    "student_attendance_marked_total", "Total number of attendance records marked"
)

student_total = Gauge(
    "student_total", "Total number of students in the system"
)

student_operations = Counter(
    "student_operations_total", "Total student operations", ["operation"]
)

# Class Metrics
class_total = Gauge(
    "class_total", "Total number of classes"
)

class_operations = Counter(
    "class_operations_total", "Total class operations", ["operation"]
)

# Assignment Metrics
assignment_total = Gauge(
    "assignment_total", "Total number of assignments", ["status"]
)

assignment_operations = Counter(
    "assignment_operations_total", "Total assignment operations", ["operation"]
)

# Announcement Metrics
announcement_total = Gauge(
    "announcement_total", "Total number of announcements", ["pinned"]
)

announcement_operations = Counter(
    "announcement_operations_total", "Total announcement operations", ["operation"]
)

# Database Metrics
db_query_duration_seconds = Histogram(
    "db_query_duration_seconds", "Database query duration in seconds", ["operation"]
)

db_connection_errors = Counter(
    "db_connection_errors_total", "Total database connection errors"
)

# Authentication Metrics
auth_attempts = Counter(
    "auth_attempts_total", "Total authentication attempts", ["status"]
)

active_sessions = Gauge(
    "active_sessions", "Number of active user sessions"
)

# Application Info
app_info = Info("flask_app_info", "Application information")
app_info.info({"version": "1.0.0", "app": "student-portal"})
