# Docker Exercises — Day 2

Hands-on exercises from the LivingDevOps Bootcamp session. Covers volumes, Dockerfile, image building, pushing to Docker Hub, and Docker Compose.

---

## Prerequisites

- Docker Desktop installed and running
- Day 1 exercises completed (containers, networking basics)
- A free Docker Hub account — create one at [hub.docker.com](https://hub.docker.com)
- Python sample app code from the bootcamp GitHub repo

---

## Exercise 1 — The Data Problem (Why Volumes Exist)

**Goal:** Understand why container data is ephemeral and why you need volumes.

```bash
# Run an alpine container interactively
docker run -it --name data-test alpine sh

# Inside the container, create a log file
echo "my important logs" > /tmp/log.txt
cat /tmp/log.txt
exit

# Remove the container
docker rm -f data-test

# Run a brand new container with the same image
docker run -it --name data-test2 alpine sh

# Check if your file is there
cat /tmp/log.txt   # File not found
exit

docker rm -f data-test2
```

**Questions to answer:**
- Why did the file disappear when you created a new container?
- In production, what kind of data would you lose if you relied on container storage alone?

---

## Exercise 2 — Host Path Mount

**Goal:** Mount a local directory into a container so data survives container restarts.

```bash
# Create a local directory with some data
mkdir -p ~/datapoints
echo "file from host" > ~/datapoints/log1.txt

# Run a container and mount the local path
docker run -it \
  --name host-mount \
  -v ~/datapoints:/data \
  alpine sh

# Inside the container
ls /data           # You should see log1.txt
cat /data/log1.txt

# Write a new file from inside the container
echo "file from container" > /data/log2.txt
exit

# Back on your host machine — the file written inside the container is here
ls ~/datapoints    # You should see both log1.txt and log2.txt
cat ~/datapoints/log2.txt
```

Now try read-only mount:

```bash
docker run -it \
  --name readonly-mount \
  -v ~/datapoints:/data:ro \
  alpine sh

# Inside the container — try to write
echo "trying to write" > /data/newfile.txt   # Should fail — read-only file system
cat /data/log1.txt                            # Reading works fine
exit

docker rm -f readonly-mount
```

**Questions to answer:**
- When would you use a read-only mount in production? (Hint: think nginx config files)
- What is the difference between `-v ~/datapoints:/data` and `-v ~/datapoints:/data:ro`?

---

## Exercise 3 — Sharing Data Across Multiple Containers

**Goal:** Mount the same path to two containers and see them share data.

```bash
mkdir -p ~/shared-data

# Start two containers mounting the same host path
docker run -dt --name writer -v ~/shared-data:/data alpine
docker run -dt --name reader -v ~/shared-data:/data alpine

# Write from the writer container
docker exec -it writer sh
echo "data from writer container" > /data/shared.txt
exit

# Read from the reader container
docker exec -it reader sh
cat /data/shared.txt   # Data written by writer is visible here
exit

# Clean up
docker rm -f writer reader
```

**Questions to answer:**
- What problem could occur if two containers write to the same file at exactly the same time?
- In production on AWS, which service would you use to share storage across multiple containers — EBS or EFS? Why?

---

## Exercise 4 — Named Docker Volumes

**Goal:** Use Docker-managed volumes instead of raw host paths.

```bash
# Create a named volume
docker volume create april-batch

# List volumes
docker volume ls

# Inspect it — notice the auto-generated mount point managed by Docker engine
docker volume inspect april-batch

# Mount the named volume to a container
docker run -it \
  --name vol-test \
  -v april-batch:/data \
  alpine sh

# Inside the container
echo "saved in docker volume" > /data/important.txt
exit

# Remove the container
docker rm -f vol-test

# Run a NEW container mounting the SAME volume
docker run -it \
  --name vol-test2 \
  -v april-batch:/data \
  alpine sh

# Data is still here even though the first container is gone
cat /data/important.txt
exit

docker rm -f vol-test2
```

Now try the `--mount` syntax (more explicit and production-preferred):

```bash
docker run -it \
  --name mount-syntax \
  --mount type=volume,source=april-batch,target=/data \
  alpine sh

ls /data   # Your file is still here
exit

docker rm -f mount-syntax
```

**Questions to answer:**
- What is the advantage of `--mount` over `-v` in terms of readability?
- When would you use `type=bind` instead of `type=volume`?
- Who manages the storage path when you use a named volume — you or Docker engine?

---

## Exercise 5 — Write Your First Dockerfile

**Goal:** Package a simple Python Flask app as a Docker image.

Create a project directory:

```bash
mkdir -p ~/docker-app
cd ~/docker-app
```

Create `app.py`:

```python
from flask import Flask
app = Flask(__name__)

@app.route('/')
def home():
    return '<h1>Hello from Docker!</h1>'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
```

Create `requirements.txt`:

```
flask
gunicorn
```

Create `.dockerignore`:

```
*.md
.git
__pycache__
*.pyc
.env
venv
.venv
Dockerfile
.dockerignore
```

Create `Dockerfile`:

```dockerfile
FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "app:app"]
```

Build the image:

```bash
docker build -t static-app:1.0 .

# Check the image was created
docker images static-app
```

**Questions to answer:**
- Why do we `COPY requirements.txt` separately before `COPY . .`?
- What does `WORKDIR /app` do?
- Why is `gunicorn` used instead of running `python app.py` directly?

---

## Exercise 6 — Docker Layer Caching in Action

**Goal:** Understand how caching speeds up rebuilds and why instruction order matters.

```bash
# Build 1 — everything runs from scratch, note the time
docker build -t static-app:1.0 .

# Make a small change to app.py only (change the return text)
# Then rebuild
docker build -t static-app:2.0 .
# Observe: FROM = CACHED, COPY requirements = CACHED,
# RUN pip install = CACHED, COPY . . = re-runs
```

Now break the cache intentionally:

```bash
# Add a new line to requirements.txt
echo "requests" >> requirements.txt

docker build -t static-app:3.0 .
# pip install re-runs because requirements.txt changed
# Everything after that layer also re-runs
```

Now swap the instruction order to see the problem:

```dockerfile
# Bad order — try this temporarily
FROM python:3.13-slim
WORKDIR /app
COPY . .                        # Code copied first
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "app:app"]
```

```bash
docker build -t static-app-bad:1.0 .

# Now change just one line in app.py and rebuild
docker build -t static-app-bad:2.0 .
# pip install re-runs every time any code file changes — much slower
```

**Questions to answer:**
- Why does changing `app.py` NOT re-run `pip install` in the correct order?
- What is the rule of thumb for ordering Dockerfile instructions to maximise caching?

---

## Exercise 7 — Compare Image Sizes

**Goal:** See the real size difference between base images.

```bash
# Build with full Python image — temporarily change FROM to: python:3.13
docker build -t static-app-full:1.0 .

# Build with slim image — change FROM back to: python:3.13-slim
docker build -t static-app-slim:1.0 .

# Pull ubuntu to compare
docker pull ubuntu

# Compare all sizes
docker images | grep -E "static-app|ubuntu|python"
```

**Questions to answer:**
- What is the size difference between the full and slim Python image?
- What is the tradeoff of using a smaller base image?
- A developer hands you a Dockerfile using `ubuntu` as the base for a Python app. What would you suggest and why?

---

## Exercise 8 — Run Your Container with Port Forwarding

**Goal:** Access your containerised app from your browser.

```bash
# Run with port forwarding — host 8082 maps to container 8000
docker run -dt \
  --name my-app \
  -p 8082:8000 \
  static-app:2.0

# Check port mapping
docker ps

# Test from terminal
curl http://localhost:8082

# Open in browser: http://localhost:8082
```

Now prove port forwarding is required:

```bash
# Run WITHOUT -p
docker run -dt --name no-port-app static-app:2.0

# Fails from host
curl http://localhost:8000

# Works from INSIDE the container
docker exec -it no-port-app sh
curl http://localhost:8000
exit

# Clean up
docker rm -f my-app no-port-app
```

**Questions to answer:**
- Why does the app work from inside the container but not from outside?
- In production on AWS ECS or EKS, do you use port forwarding like this? What handles external traffic instead?

---

## Exercise 9 — Override Startup with ENTRYPOINT

**Goal:** Change the default startup command at runtime without rebuilding the image.

```bash
# Default CMD runs gunicorn — override it to run python directly
docker run -dt \
  --name entrypoint-test \
  --entrypoint python \
  static-app:2.0 app.py

docker logs entrypoint-test

docker rm -f entrypoint-test
```

**Questions to answer:**
- When would `--entrypoint` be useful in a real ECS or Kubernetes setup? (Hint: database migrations, one-off jobs)
- What is the difference between `CMD` and `ENTRYPOINT` in a Dockerfile?
- Should you define `ENTRYPOINT` inside the Dockerfile? Why or why not?

---

## Exercise 10 — Tag and Push to Docker Hub

**Goal:** Share your image so anyone can pull and run it.

```bash
# Log in to Docker Hub
docker login

# Tag your local image with your Docker Hub username
docker tag static-app:2.0 <your-dockerhub-username>/static-app:1.0

# Verify — same image ID, new name
docker images | grep static-app

# Push
docker push <your-dockerhub-username>/static-app:1.0
```

Pull and run from Docker Hub (test on another machine or ask a peer):

```bash
docker pull <your-dockerhub-username>/static-app:1.0
docker run -dt -p 8082:8000 <your-dockerhub-username>/static-app:1.0
curl http://localhost:8082
```

**For Mac M1/M2 users — multi-platform build:**

```bash
# Build for Linux AMD64 (EC2 / most servers)
docker build --platform linux/amd64 \
  -t <your-dockerhub-username>/static-app:amd64 .

# Build for ARM64 (Mac M1/M2)
docker build --platform linux/arm64 \
  -t <your-dockerhub-username>/static-app:arm64 .

docker push <your-dockerhub-username>/static-app:amd64
docker push <your-dockerhub-username>/static-app:arm64
```

**Questions to answer:**
- Why do images built on Mac M1 sometimes fail to run on EC2?
- In a company using AWS, which private registry would you use instead of Docker Hub? What are the benefits?

---

## Exercise 11 — Docker Compose: Two-Tier App

**Goal:** Run a Flask app and PostgreSQL together with one command.

```bash
mkdir -p ~/compose-app
cd ~/compose-app
```

Copy your `app.py`, `requirements.txt`, `Dockerfile`, and `.dockerignore` here. Then create `docker-compose.yml`:

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: appdb
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - app-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  app:
    build:
      context: .
    ports:
      - "8082:8000"
    environment:
      DATABASE_URL: postgresql://appuser:mypassword@postgres:5432/appdb
    networks:
      - app-network
    depends_on:
      postgres:
        condition: service_healthy
    restart: on-failure:3

volumes:
  pgdata:

networks:
  app-network:
```

Run it:

```bash
# Start all services
docker compose up

# In a separate terminal
docker ps
curl http://localhost:8082

# Stop everything
docker compose down

# Stop and wipe all volumes (resets the database)
docker compose down -v
```

**Questions to answer:**
- Why does the app use `postgres` as the database hostname instead of `localhost`?
- What does the `volumes` block at the bottom of the file do — and why do you also reference the volume inside the `postgres` service?
- Why is `restart: on-failure:3` set to 3 and not unlimited?
- Why is Docker Compose not recommended for production?

---

## Exercise 12 — Simulate the Startup Race Condition

**Goal:** See what happens when the app starts before PostgreSQL is ready.

Edit `docker-compose.yml` — remove the healthcheck and simplify `depends_on`:

```yaml
    depends_on:
      - postgres
    # remove restart line too
```

Also temporarily change the app's CMD to `python app.py` (no gunicorn).

```bash
docker compose down -v
docker compose up

# Watch the logs — app will crash trying to connect to a database that isn't ready
docker compose logs app
```

Restore the healthcheck:

```bash
docker compose down -v
# Restore healthcheck and condition: service_healthy
docker compose up
docker compose logs app   # App now waits properly
```

**Questions to answer:**
- Why did gunicorn sometimes hide this failure in the demo?
- What does `pg_isready` actually check inside the postgres container?
- What is `start_period` in the healthcheck config used for?

---

## Cleanup

```bash
docker compose down -v

docker rm -f $(docker ps -aq)

docker rmi -f $(docker images -q)

docker volume prune

docker network prune
```

---

## Summary Checklist

Before the next class, make sure you can do the following without looking at notes:

- [ ] Explain why container data is lost when a container is removed
- [ ] Mount a host path using `-v` and `--mount type=bind`
- [ ] Create a named Docker volume and mount it using `--mount type=volume`
- [ ] Write a Dockerfile for a Python Flask app from scratch
- [ ] Explain what each Dockerfile instruction does: `FROM`, `WORKDIR`, `COPY`, `RUN`, `EXPOSE`, `CMD`
- [ ] Explain Docker layer caching and why instruction order matters
- [ ] Build an image, tag it, and push it to Docker Hub
- [ ] Run a container with port forwarding and access it in the browser
- [ ] Write a `docker-compose.yml` with a healthcheck, dependency condition, named volume, and custom network
- [ ] Explain the startup race condition and how `condition: service_healthy` solves it
- [ ] Explain why Docker Compose is for local testing, not production

---

## Coming Up Next Class

- Docker Compose project — full three-tier app (frontend + backend + database)
- Monitoring and alerting setup with containers
- Why Docker Compose is not enough at scale
- Moving to managed container services — AWS ECS and Kubernetes
