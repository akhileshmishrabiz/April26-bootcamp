# Day 9 — ECS Student Portal

Flask student portal with DevOps retros, containerized for AWS ECS.

Location: `April26-bootcamp/day9-ecs-terraform/src`

## Run locally

```bash
cd day9-ecs-terraform/src
docker compose up --build
```

- App: http://localhost:8000
- Health: http://localhost:8000/health

## Admin account (auto-created on startup)

| Field    | Value                 |
|----------|-----------------------|
| Email    | livingdevops@gmail.com |
| Username | livingdevops          |
| Password | LivingDevops1!        |

Override password with `ADMIN_PASSWORD` env var.

## DevOps Retro feature

- **Admin** creates retro boards at `/retro/create`
- **Share link** on each board — copy and send to the team
- Join page (`/retro/join/<token>`) offers:
  - **Guest join** — enter a display name, no account needed
  - **Login / Register** — redirects back to the retro after sign-in
- Sticky notes in 3 columns: Went Well · Needs Improvement · Action Items
- Like cards and comment to discuss
- Admin can close a retro when done

## Tests

```bash
pytest
```
