# Kubernetes Volume Snapshot Tool

Herramienta automatizada para la gestión de snapshots de volúmenes persistentes (PVC) en Kubernetes, con capacidades de creación automática y limpieza de snapshots antiguos.

## 📋 Descripción

Esta herramienta permite:
- **Crear snapshots automáticos** de PVCs específicos o todos los PVCs del cluster
- **Limpiar snapshots antiguos** basado en políticas de retención
- **Filtrar PVCs objetivo** mediante configuración flexible
- **Logging detallado** con timestamps para auditoría
- **Modo dry-run** para simulación sin cambios reales

## 🏗️ Arquitectura

### Componentes

- **`entrypoint.sh`**: Script principal con toda la lógica de snapshots
- **`Dockerfile`**: Imagen Docker con kubectl, jq y dependencias necesarias
- **`config-bk.env`**: Archivo de configuración con variables de entorno
- **`.github/workflows/deploy.yaml`**: Pipeline CI/CD para construcción automática

### Funciones Principales

1. **`create_snapshots()`**: Crea snapshots individuales usando VolumeSnapshot API
2. **`cleanup_old_snapshots()`**: Elimina snapshots basado en edad y políticas
3. **`is_pvc_in_target_list()`**: Filtra PVCs según lista de objetivos configurada

## 🚀 Uso

### Ejecución Local

```bash
# Configurar variables de entorno
export TARGET_PVCS="dgraph,postgres"
export MAX_AGE_DAYS=7
export DRY_RUN=false

# Ejecutar script
./entrypoint.sh
```

### Ejecución con Docker

```bash
# Construir imagen
docker build -t snapshot-tool:latest .

# Ejecutar con configuración
docker run --rm \
  -v ~/.kube:/root/.kube:ro \
  --env-file config-bk.env \
  snapshot-tool:latest
```

### Despliegue en Kubernetes

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: volume-snapshot-tool
spec:
  schedule: "0 2 * * *"  # Diario a las 2:00 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: snapshot-tool
            image: eklegein/snapshot-tool:0.0.1
            env:
            - name: TARGET_PVCS
              value: "dgraph"
            - name: MAX_AGE_DAYS
              value: "7"
            - name: DRY_RUN
              value: "false"
          restartPolicy: OnFailure
```

## ⚙️ Configuración

### Variables de Entorno

| Variable | Descripción | Valor por Defecto | Ejemplo |
|----------|-------------|-------------------|---------|
| `TARGET_PVCS` | Lista de PVCs a procesar (separados por coma) | `""` (todos) | `"dgraph,postgres"` |
| `MAX_AGE_DAYS` | Días de retención para snapshots | `7` | `14` |
| `DRY_RUN` | Modo simulación (no elimina snapshots) | `false` | `true` |

### Archivo de Configuración

**`config-bk.env`**:
```bash
TARGET_PVCS="dgraph"
MAX_AGE_DAYS=2
DRY_RUN=false
```

## 📊 Logging y Monitoreo

### Niveles de Log

- **`[INFO]`**: Operaciones normales y progreso
- **`[WARN]`**: Advertencias no críticas
- **`[ERROR]`**: Errores que requieren atención

### Ejemplo de Output

```
[INFO]  2025-09-21 15:17:55 Processing specific PVCs: dgraph
[INFO]  2025-09-21 15:17:56 Creating snapshot for pvc: datadir-dgraph-0 in namespace: dgraph
[INFO]  2025-09-21 15:17:56 Attempting to create snapshot: snapshot-datadir-dgraph-0-20250921-151756
[INFO]  2025-09-21 15:17:56 ✓ Snapshot created successfully
[INFO]  2025-09-21 15:17:56 Starting cleanup of snapshots older than 2 days
[INFO]  2025-09-21 15:17:56 === CLEANUP SUMMARY ===
[INFO]  2025-09-21 15:17:56 Snapshots found: 4
[INFO]  2025-09-21 15:17:56 Snapshots deleted: 0
[INFO]  2025-09-21 15:17:56 Errors encountered: 0
```

## 🔧 Requisitos Técnicos

### Dependencias del Sistema

- **kubectl** v1.32.0+
- **jq** para procesamiento JSON
- **bash** 4.0+
- **curl** para descargas

### Permisos de Kubernetes

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: snapshot-tool
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots"]
  verbs: ["get", "list", "create", "delete"]
```

### Storage Class Requerido

La herramienta usa `topolvm-provisioner-thin` como VolumeSnapshotClassName. Asegúrate de que esté disponible:

```bash
kubectl get volumesnapshotclass
```

## 🔄 CI/CD Pipeline

### GitHub Actions

El workflow automatizado:
- **Trigger**: Push a `main` o ejecución manual
- **Build**: Construye imagen Docker multi-arquitectura
- **Registry**: Publica en Docker Hub como `eklegein/snapshot-tool`
- **Versioning**: Usa tags semánticos (v0.0.1)

### Configuración del Pipeline

```yaml
jobs:
  build_docker:
    uses: eklegein/shared-workflow/.github/workflows/build-backend.yaml@main
    with:
      docker_image_name: "snapshot-tool"
      release_version: "0.0.1"
      docker_registry_url: "eklegein"
```

## 🛠️ Desarrollo

### Estructura del Proyecto

```
tools/
├── README.md                    # Esta documentación
├── Dockerfile                   # Imagen Docker
├── entrypoint.sh               # Script principal
├── config-bk.env              # Configuración de ejemplo
└── .github/
    └── workflows/
        └── deploy.yaml         # Pipeline CI/CD
```

### Testing Local

```bash
# Modo dry-run para testing
export DRY_RUN=true
export TARGET_PVCS="test-pvc"
./entrypoint.sh
```

### Debug Mode

Para habilitar logs de debug, la función `is_pvc_in_target_list()` incluye logs detallados que muestran el proceso de matching de PVCs.

## 🚨 Consideraciones de Seguridad

1. **Permisos mínimos**: Usa RBAC con permisos específicos
2. **Secrets management**: No hardcodear credenciales en el código
3. **Network policies**: Restringir acceso de red si es necesario
4. **Resource limits**: Configurar límites de CPU/memoria en Kubernetes

## 📈 Mejoras Futuras

- [ ] Soporte para múltiples VolumeSnapshotClass
- [ ] Integración con sistemas de monitoreo (Prometheus)
- [ ] Notificaciones por email/Slack en caso de errores
- [ ] Backup a almacenamiento externo (S3, GCS)
- [ ] Interface web para gestión visual

## 🤝 Contribución

1. Fork del repositorio
2. Crear branch feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -am 'Añadir nueva funcionalidad'`)
4. Push al branch (`git push origin feature/nueva-funcionalidad`)
5. Crear Pull Request

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver archivo `LICENSE` para más detalles.

---

**Mantenido por**: Equipo DevOps Eklegein  
**Versión**: 0.0.1  
**Última actualización**: 2025-09-21
