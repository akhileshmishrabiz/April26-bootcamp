Top 4xx (Client Errors)

400 Bad Request – malformed syntax or invalid request from client
401 Unauthorized – missing/invalid authentication credentials
403 Forbidden – authenticated but not permitted to access resource
404 Not Found – resource doesn't exist
429 Too Many Requests – rate limit exceeded
timeout -> 

Top 5xx (Server Errors)

500 Internal Server Error – generic server-side failure
502 Bad Gateway – upstream server sent invalid response (common with reverse proxies/load balancers)
503 Service Unavailable – server overloaded or down for maintenance
504 Gateway Timeout – upstream server didn't respond in time
507 Insufficient Storage – server ran out of storage to complete request