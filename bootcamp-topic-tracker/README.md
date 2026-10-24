# Bootcamp Topic Tracker

A small, focused board for tracking completed and upcoming bootcamp topics.

## Features

- Add columns horizontally
- Add topic points vertically within any column
- Drag topics between columns
- Automatic progress calculation
- Browser-local persistence (no database required)
- Responsive layout

## Run with Docker

```bash
docker build -t bootcamp-topic-tracker .
docker run -d --name bootcamp-topic-tracker -p 8080:80 bootcamp-topic-tracker
```

Open <http://localhost:8080>.

To stop and remove the container:

```bash
docker rm -f bootcamp-topic-tracker
```
