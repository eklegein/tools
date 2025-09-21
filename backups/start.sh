#!/bin/bash

# Script simple para desarrollo
set -e

# Construir la imagen
echo "Building snapshot container..."
docker build -t snapshot-tool .

# Ejecutar el contenedor con configuración de desarrollo
echo "Running snapshot container..."
docker run --rm \
  --env-file config-bk.env \
  -v ~/.kube:/root/.kube:ro \
  snapshot-tool