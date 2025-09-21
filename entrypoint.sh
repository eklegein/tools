#!/bin/bash

set -o pipefail

DATE=$(date +%m-%d-%Y)

# --- Logging helpers ---
log_info() {
    echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_warn() {
    echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Captura cualquier error no manejado
trap 'log_error "Error en línea $LINENO (código $?)"' ERR

function create_snapshots() {
    local namespace="$1"
    local pvc_name="$2"
    local snapshot_name="snapshot-${pvc_name}-$(date +%Y%m%d-%H%M%S)"
    
    log_info "Attempting to create snapshot: $snapshot_name"
    log_info "  PVC: $pvc_name"
    log_info "  Namespace: $namespace"
    
    local result
    result=$(kubectl apply -f - 2>&1 <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${snapshot_name}
  namespace: ${namespace}
spec:
  volumeSnapshotClassName: topolvm-provisioner-thin
  source:
    persistentVolumeClaimName: ${pvc_name}
EOF
)
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "✓ Snapshot created successfully"
        log_info "  kubectl output: $result"
    else
        log_error "✗ Snapshot creation failed"
        log_error "  kubectl error: $result"
    fi
    
    return $exit_code
}

function cleanup_old_snapshots() {
    local max_age_days="${1:-7}"  # Por defecto 7 días
    local dry_run="${2:-false}"   # Por defecto ejecuta, no simula
    
    log_info "Starting cleanup of snapshots older than $max_age_days days"
    
    if [ "$dry_run" = "true" ]; then
        log_info "DRY RUN MODE - No snapshots will be deleted"
    fi
    
    local total_found=0
    local total_deleted=0
    local total_errors=0
    
    # Obtener todos los snapshots con su fecha de creación
    kubectl get volumesnapshots --all-namespaces -o json | jq -r '
        .items[] | 
        select(.metadata.creationTimestamp != null) |
        "\(.metadata.namespace) \(.metadata.name) \(.metadata.creationTimestamp)"
    ' | while read -r namespace snapshot_name creation_time; do
        
        if [ -z "$creation_time" ] || [ "$creation_time" = "null" ]; then
            log_warn "Skipping snapshot $snapshot_name: no creation timestamp"
            continue
        fi
        
        ((total_found++))
        
        # Convertir timestamp a epoch (segundos desde 1970)
        local snapshot_epoch
        snapshot_epoch=$(date -d "$creation_time" +%s 2>/dev/null)
    
        # Si falla el parsing directo, intentar con formato ISO 8601
        if [ -z "$snapshot_epoch" ]; then
            # Convertir formato ISO 8601 a formato que entiende date nativo de macOS
            local formatted_time
            if [[ "$creation_time" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$ ]]; then
                # Formato: YYYY-MM-DDTHH:MM:SSZ -> MM/DD/YYYY HH:MM:SS
                formatted_time="${BASH_REMATCH[2]}/${BASH_REMATCH[3]}/${BASH_REMATCH[1]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
                
                snapshot_epoch=$(date -j -f "%m/%d/%Y %H:%M:%S" "$formatted_time" +%s 2>/dev/null)
            fi
        fi

        if [ -z "$snapshot_epoch" ]; then
            log_error "Failed to parse creation time for snapshot $snapshot_name: $creation_time"
            ((total_errors++))
            continue
        fi
        
        # Calcular edad en días
        local current_epoch=$(date +%s)
        local age_days=$(( (current_epoch - snapshot_epoch) / 86400 ))
        
        log_info "Snapshot: $snapshot_name (namespace: $namespace) - Age: $age_days days"
        
        if [ $age_days -gt $max_age_days ]; then
            log_info "  → Snapshot is $age_days days old (> $max_age_days days) - marked for deletion"
            
            if [ "$dry_run" = "true" ]; then
                log_info "  → [DRY RUN] Would delete: kubectl delete volumesnapshot $snapshot_name -n $namespace"
                ((total_deleted++))
            else
                log_info "  → Deleting snapshot: $snapshot_name"
                
                local delete_result
                delete_result=$(kubectl delete volumesnapshot "$snapshot_name" -n "$namespace" 2>&1)
                local delete_exit_code=$?
                
                if [ $delete_exit_code -eq 0 ]; then
                    log_info "  → ✓ Deleted successfully: $delete_result"
                    ((total_deleted++))
                else
                    log_error "  → ✗ Failed to delete: $delete_result"
                    ((total_errors++))
                fi
            fi
        else
            log_info "  → Snapshot is $age_days days old (≤ $max_age_days days) - keeping"
        fi
    done
    
    # Resumen final
    log_info "=== CLEANUP SUMMARY ==="
    log_info "Snapshots found: $total_found"
    log_info "Snapshots deleted: $total_deleted"
    log_info "Errors encountered: $total_errors"
    
    if [ $total_errors -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Función para verificar si un PVC está en la lista de PVCs objetivo
function is_pvc_in_target_list() {
    local pvc_name="$1"
    local target_list="$2"
    
    if [ -z "$target_list" ]; then
        return 0  # Si no hay lista, procesar todos
    fi
    
    # Limpiar comillas dobles de la target_list
    target_list=$(echo "$target_list" | tr -d '"')
    
    log_info "DEBUG: Checking PVC '$pvc_name' against cleaned target list: '$target_list'"
    
    # Convertir lista separada por comas/espacios en array
    IFS=', ' read -ra target_array <<< "$target_list"
    
    for target_pvc in "${target_array[@]}"; do
        log_info "DEBUG: Comparing '$pvc_name' with target '$target_pvc'"
        if [[ "$pvc_name" == *"$target_pvc"* ]]; then
            log_info "DEBUG: ✓ Match found!"
            return 0  # PVC encontrado en la lista
        fi
    done
    
    log_info "DEBUG: ✗ No match found"
    return 1  # PVC no encontrado en la lista
}

# Variable de entorno para PVCs específicos (opcional)
TARGET_PVCS="${TARGET_PVCS:-}"

if [ -n "$TARGET_PVCS" ]; then
    log_info "Processing specific PVCs: $TARGET_PVCS"
else
    log_info "Processing all PVCs in the cluster"
fi

kubectl get pvc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | while read -r namespace pvc_name; do
    if [ "$pvc_name" = "<none>" ] || [ -z "$pvc_name" ]; then
        log_info "snapshot not found"
        continue
    fi
    
    # Verificar si el PVC está en la lista objetivo (si se especifica)
    if ! is_pvc_in_target_list "$pvc_name" "$TARGET_PVCS"; then
        log_info "Skipping PVC $pvc_name (not in target list)"
        continue
    fi
     
    log_info "Creating snapshot for pvc: ${pvc_name} in namespace: ${namespace}"
    
    if create_snapshots "$namespace" "$pvc_name"; then
        log_info "Snapshot process completed for $pvc_name"
    else
        log_error "Failed to create snapshot for $pvc_name"
    fi
done

cleanup_old_snapshots $MAX_AGE_DAYS $DRY_RUN