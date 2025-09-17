version: '3.8'
services:
  mockapi:
    image: mockoon/cli:latest
    ports: ["3001:3001"]
    volumes: ["./test/mocks:/data"]
    command: ["--data", "/data/mock-config.json", "--port", "3001"]
