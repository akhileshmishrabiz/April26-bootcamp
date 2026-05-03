
docker pull livingdevopswithakhilesh/april-batch:1.0


docker run -td -p 8082:8000 livingdevopswithakhilesh/april-batch:1.0


# Build for AMD64 (x86_64) - Intel/AMD processors, most cloud servers
docker build --platform linux/amd64 -t livingdevopswithakhilesh/april-batch:2.0-amd64 .

# Build for ARM64 - Apple Silicon (M1/M2/M3), AWS Graviton, Raspberry Pi 4+
docker build --platform linux/arm64 -t livingdevopswithakhilesh/april-batch:2.0-arm64 .