#!/bin/ash
set -eu

# ---------------------------------------------------------------------
# Core execution context
# ---------------------------------------------------------------------

OUTPUT_ROOT="${1:-/tmp/triage}"
mkdir -p "${OUTPUT_ROOT}"

LOG_FILE="${LOG_FILE:-${OUTPUT_ROOT}/_deploy.log}"

# ---------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date
}

log_event() {
  printf '%s %s\n' "$(timestamp_utc)" "$*" >>"${LOG_FILE}"
}

resolve_output_path() {
  printf '%s/%s' "${OUTPUT_ROOT}" "$1"
}

mkparent() {
  local full_path="$(resolve_output_path "$1")"
  local parent_dir="${full_path%/*}"

  [ "${parent_dir}" != "${full_path}" ] && mkdir -p "${parent_dir}"

  printf '%s' "${full_path}"
}

mkdir_out() {
  local dir_path="$(resolve_output_path "$1")"
  mkdir -p "${dir_path}"
  printf '%s' "${dir_path}"
}

task_id_to_function_name() {
  printf 'task_%s' "$(printf '%s' "$1" | tr '.' '_')"
}

# ---------------------------------------------------------------------
# Task execution wrapper
# ---------------------------------------------------------------------

run_task() {
  local task_id="$1"
  local task_output_path="${2:-}"

  local function_name
  function_name="$(task_id_to_function_name "${task_id}")"

  log_event "START ${task_id} ${task_output_path}"

  command -v "${function_name}" >/dev/null 2>&1 || {
    log_event "FAIL  ${task_id} missing_function=${function_name}"
    return 0
  }

  set +e

  (
    set -x
    "${function_name}" "${OUTPUT_ROOT}" "${LOG_FILE}" "${task_output_path}"
  ) >>"${LOG_FILE}" 2>&1

  local exit_code="$?"

  set -e

  if [ "${exit_code}" -ne 0 ]; then
    log_event "FAIL  ${task_id} exit_code=${exit_code} ${task_output_path}"
  else
    log_event "END   ${task_id} ${task_output_path}"
  fi

  return 0
}

log_event "EVIDENCE_ROOT_INITIALISED path=${OUTPUT_ROOT}"

# ---------------------------------------------------------------------
# Global Capability Detection
# ---------------------------------------------------------------------

TAR_AVAILABLE=0
if command -v tar >/dev/null 2>&1; then
  TAR_AVAILABLE=1
fi

GZIP_AVAILABLE=0
if command -v gzip >/dev/null 2>&1; then
  GZIP_AVAILABLE=1
fi

HASH_CMD=""
for h in sha256sum sha512sum sha3sum sha1sum md5sum; do
  if command -v "$h" >/dev/null 2>&1; then
    HASH_CMD="$h"
    break
  fi
done

HASH_AVAILABLE=0
[ -n "$HASH_CMD" ] && HASH_AVAILABLE=1

log_event "GLOBAL_CAPABILITY hash=${HASH_AVAILABLE} hash_cmd=${HASH_CMD:-none} tar=${TAR_AVAILABLE} gzip=${GZIP_AVAILABLE}"


# ---------------------------------------------------------------------
# Tasks list defined as functions
# ---------------------------------------------------------------------

task_ALPINE_PROCESS_PS_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  ps -o pid,ppid,pgid,user,group,etime,nice,rgroup,ruser,time,tty,vsz,sid,stat,rss,comm,args \
    >"${output_file}" 2>>"${LOG}"
}

task_ALPINE_PROCESS_HIDDEN_PROCESSES_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  : >"${output_file}"
  
  visible_pids="$(ps -o pid 2>>"${LOG}" | awk 'BEGIN{s=":"} $1 ~ /^[0-9]+$/ {s=s $1 ":"} END{print s}')"
  
  if [ "${visible_pids}" != ":" ]; then
    for d in /proc/[0-9]*; do
      [ -d "${d}" ] || continue
  
      pid="${d##*/}"
  
      case "${visible_pids}" in
        *":${pid}:"*) : ;;
        *) printf '%s\n' "${pid}" ;;
      esac
    done >>"${output_file}"
  else
    printf '%s\n' "Error: could not gather visible PIDs from ps output." >>"${output_file}"
  fi
}

task_ALPINE_PROCESS_TOP_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v top >/dev/null 2>&1; then
    top -b -n 1 >"${output_file}" 2>>"${LOG}"
  else
    printf '%s\n' "top not present" >"${output_file}"
  fi
}

task_ALPINE_PROCESS_LSOF_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v lsof >/dev/null 2>&1; then
    lsof >"${output_file}" 2>>"${LOG}"
  else
    printf '%s\n' "lsof not present" >"${output_file}"
  fi
}

task_ALPINE_PROCESS_PROC_1() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_dir="$(mkdir_out "${TASK_OUTPUT}")"
  
  for d in /proc/[0-9]*; do
    [ -d "${d}" ] || continue
  
    pid="${d##*/}"
    pid_dir="${output_dir}/${pid}"
  
    mkdir -p "${pid_dir}"
  
    for rel in comm stat status maps mounts stack cgroup; do
      src="${d}/${rel}"
      [ -e "${src}" ] || continue
      [ -r "${src}" ] || continue
  
      cat "${src}" >"${pid_dir}/${rel}.txt" 2>>"${LOG}" || true
    done
  
    for rel in cmdline environ; do
      src="${d}/${rel}"
      [ -e "${src}" ] || continue
      [ -r "${src}" ] || continue
  
      cat "${src}" >"${pid_dir}/${rel}.bin" 2>>"${LOG}" || true
    done
  
    for rel in exe cwd; do
      src="${d}/${rel}"
      [ -L "${src}" ] || continue
  
      readlink "${src}" >"${pid_dir}/${rel}.txt" 2>>"${LOG}" || true
    done
  
    src="${d}/net/unix"
    [ -r "${src}" ] && cat "${src}" >"${pid_dir}/net_unix.txt" 2>>"${LOG}" || true
  
    for rel in fd map_files; do
      src="${d}/${rel}"
      [ -d "${src}" ] && ls -la "${src}" >"${pid_dir}/ls_la_${rel}.txt" 2>>"${LOG}" || true
    done
  done
}

task_ALPINE_PROCESS_PSTREE_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v pstree >/dev/null 2>&1; then
    pstree -p \
      >"${output_file}" \
      2>>"${LOG}"
  else
    printf '%s\n' "pstree not present" >"${output_file}"
  fi
}

task_ALPINE_PROCESS_HASH_RUNNING_PROCESSES_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  : >"${output_file}"
  
  if [ "${HASH_AVAILABLE:-0}" -eq 1 ]; then
    printf '%s\n' "HASH_ALG=${HASH_CMD}" >>"${output_file}"
  
    for exe_link in /proc/[0-9]*/exe; do
      [ -L "${exe_link}" ] || continue
  
      target="$(readlink "${exe_link}" 2>>"${LOG}" || true)"
      [ -n "${target}" ] || continue
  
      case "${target}" in
        *" (deleted)"*)
          printf '%s\n' "DELETED ${target}" >>"${output_file}"
          continue
          ;;
      esac
  
      if [ -r "${target}" ]; then
        "${HASH_CMD}" "${target}" >>"${output_file}" 2>>"${LOG}" || true
      else
        printf '%s\n' "UNREADABLE ${target}" >>"${output_file}"
      fi
    done
  
  else
    printf '%s\n' "hashing not available" >>"${output_file}"
  fi
}

task_ALPINE_PROCESS_STRINGS_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_dir="$(mkdir_out "${TASK_OUTPUT}")"
  status_file="${output_dir}/_strings_status.txt"
  
  : >"${status_file}"
  
  HAS_STRINGS=""
  if command -v strings >/dev/null 2>&1; then
    HAS_STRINGS=1
  fi
  
  if [ -z "${HAS_STRINGS}" ]; then
    printf '%s\n' "strings not present" >>"${status_file}"
  else
    if [ "${GZIP_AVAILABLE}" -eq 1 ]; then
      printf '%s\n' "gzip present; writing strings.txt.gz per PID" >>"${status_file}"
    else
      printf '%s\n' "gzip not present; writing strings.txt per PID" >>"${status_file}"
    fi
  
    for d in /proc/[0-9]*; do
      [ -d "${d}" ] || continue
      [ -L "${d}/exe" ] || continue
  
      pid="${d##*/}"
      pid_dir="${output_dir}/${pid}"
  
      mkdir -p "${pid_dir}" 2>/dev/null || true
  
      if [ "${GZIP_AVAILABLE}" -eq 1 ]; then
        strings -a "${d}/exe" 2>>"${LOG}" | gzip >"${pid_dir}/strings.txt.gz" 2>>"${LOG}" || true
      else
        strings -a "${d}/exe" >"${pid_dir}/strings.txt" 2>>"${LOG}" || true
      fi
    done
  fi
}

task_ALPINE_PROCESS_DELETED_RECOVERY_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_dir="$(mkdir_out "${TASK_OUTPUT}")"
  report_file="${output_dir}/_deleted_recovery_report.txt"
  
  : >"${report_file}"
  
  for d in /proc/[0-9]*; do
    [ -d "${d}" ] || continue
  
    pid="${d##*/}"
  
    [ -L "${d}/exe" ] || continue
  
    target="$(readlink "${d}/exe" 2>>"${LOG}" || true)"
    [ -n "${target}" ] || continue
  
    case "${target}" in
      *" (deleted)"*) : ;;
      *) continue ;;
    esac
  
    case "${target}" in
      /proc/*)
        printf '%s\n' "SKIP PID=${pid} EXE=${target} (target under /proc)" >>"${report_file}"
        continue
        ;;
    esac
  
    pid_dir="${output_dir}/${pid}"
    mkdir -p "${pid_dir}"
  
    printf '%s\n' "RECOVER_EXE PID=${pid} EXE=${target} -> ${TASK_OUTPUT}/${pid}/recovered_exe.bin (max 20MiB)" >>"${report_file}"
  
    dd if="/proc/${pid}/exe" of="${pid_dir}/recovered_exe.bin" bs=1024 count=20000 2>>"${LOG}" || true
  
    if [ -d "${d}/fd" ]; then
      for fd in "${d}/fd"/*; do
        [ -e "${fd}" ] || continue
  
        fd_num="${fd##*/}"
  
        fd_target="$(readlink "${fd}" 2>>"${LOG}" || true)"
        [ -n "${fd_target}" ] || continue
  
        case "${fd_target}" in
          *" (deleted)"*) : ;;
          *) continue ;;
        esac
  
        case "${fd_target}" in
          /dev/*|/proc/*)
            printf '%s\n' "SKIP_FD PID=${pid} FD=${fd_num} TARGET=${fd_target} (under /dev or /proc)" >>"${report_file}"
            continue
            ;;
        esac
  
        case "${fd_target}" in
          memfd:*)
            name="recovered_memfd_${fd_num}.bin"
            ;;
          *)
            name="recovered_fd_${fd_num}.bin"
            ;;
        esac
  
        printf '%s\n' "RECOVER_FD PID=${pid} FD=${fd_num} TARGET=${fd_target} -> ${TASK_OUTPUT}/${pid}/${name} (max 20MiB)" >>"${report_file}"
  
        dd if="/proc/${pid}/fd/${fd_num}" of="${pid_dir}/${name}" bs=1024 count=20000 2>>"${LOG}" || true
      done
    fi
  done
}

task_ALPINE_NETWORK_ARP_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  arp -a >"${output_file}" 2>>"${LOG}"
}

task_ALPINE_NETWORK_PROC_NET_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_dir="$(mkdir_out "${TASK_OUTPUT}")"
  
  for protocol in tcp tcp6 udp udp6; do
    src="/proc/net/${protocol}"
    dst="${output_dir}/${protocol}.txt"
  
    if [ -r "${src}" ]; then
      cat "${src}" >"${dst}" 2>>"${LOG}"
    else
      printf '%s\n' "not present" >"${dst}"
    fi
  done
}

task_ALPINE_NETWORK_HOSTNAME_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if hostname -f >"${output_file}" 2>>"${LOG}"; then
    :
  else
    hostname >"${output_file}" 2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  fi
}

task_ALPINE_NETWORK_HOSTNAME_1() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  uname -n >"${output_file}" 2>>"${LOG}"
}

task_ALPINE_NETWORK_IFCONFIG_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  ifconfig -a >"${output_file}" 2>>"${LOG}"
}

task_ALPINE_NETWORK_IP_ADDR_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v ip >/dev/null 2>&1; then
    ip addr show >"${output_file}" 2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  else
    printf '%s\n' "ip not present" >"${output_file}"
  fi
}

task_ALPINE_NETWORK_IP_LINK_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v ip >/dev/null 2>&1; then
    ip link show >"${output_file}" 2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  else
    printf '%s\n' "ip not present" >"${output_file}"
  fi
}

task_ALPINE_NETWORK_IP_NEIGH_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v ip >/dev/null 2>&1; then
    ip neigh show >"${output_file}" 2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  else
    printf '%s\n' "ip not present" >"${output_file}"
  fi
}

task_ALPINE_NETWORK_IP_ROUTE_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v ip >/dev/null 2>&1; then
    ip route list >"${output_file}" 2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  else
    printf '%s\n' "ip not present" >"${output_file}"
  fi
}

task_ALPINE_NETWORK_NETSTAT_0() {
  local OUT="$1"
  local LOG="$2"
  local TASK_OUTPUT="$3"

  output_file="$(mkparent "${TASK_OUTPUT}")"
  
  if command -v netstat >/dev/null 2>&1; then
    netstat -an \
      >"${output_file}" \
      2>>"${LOG}" || printf '%s\n' "command failed" >"${output_file}"
  else
    printf '%s\n' "netstat not present" >"${output_file}"
  fi
}


# ---------------------------------------------------------------------
# Task Function calls
# ---------------------------------------------------------------------

run_task "ALPINE.PROCESS.PS.0" "process/ps-all.txt"

run_task "ALPINE.PROCESS.HIDDEN_PROCESSES.0" "process/hidden_pids_for_ps_command.txt"

run_task "ALPINE.PROCESS.TOP.0" "process/top_snapshot.txt"

run_task "ALPINE.PROCESS.LSOF.0" "process/lsof.txt"

run_task "ALPINE.PROCESS.PROC.1" "process/proc"

run_task "ALPINE.PROCESS.PSTREE.0" "process/pstree.txt"

run_task "ALPINE.PROCESS.HASH_RUNNING_PROCESSES.0" "process/hash_running_processes.txt"

run_task "ALPINE.PROCESS.STRINGS.0" "process/proc"

run_task "ALPINE.PROCESS.DELETED_RECOVERY.0" "process/proc"

run_task "ALPINE.NETWORK.ARP.0" "network/arp.txt"

run_task "ALPINE.NETWORK.PROC_NET.0" "network/net"

run_task "ALPINE.NETWORK.HOSTNAME.0" "network/hostname.txt"

run_task "ALPINE.NETWORK.HOSTNAME.1" "network/uname_n.txt"

run_task "ALPINE.NETWORK.IFCONFIG.0" "network/ifconfig_-a.txt"

run_task "ALPINE.NETWORK.IP.ADDR.0" "network/ip_addr.txt"

run_task "ALPINE.NETWORK.IP.LINK.0" "network/ip_link.txt"

run_task "ALPINE.NETWORK.IP.NEIGH.0" "network/ip_neigh.txt"

run_task "ALPINE.NETWORK.IP.ROUTE.0" "network/ip_route.txt"

run_task "ALPINE.NETWORK.NETSTAT.0" "network/netstat_an.txt"


log_event "RUN_END output_root=${OUTPUT_ROOT}"

archive_path="${OUTPUT_ROOT%/}.tar.gz"

# ---------------------------------------------------------------------
# Archiving
# ---------------------------------------------------------------------

ARCHIVE_CREATED=0

if [ "${TAR_AVAILABLE:-0}" -eq 1 ]; then
  if tar -czf "${archive_path}" -C "${OUTPUT_ROOT}" . >>"${LOG_FILE}" 2>&1; then
    log_event "ARCHIVE_CREATED path=${archive_path}"
    ARCHIVE_CREATED=1
  else
    log_event "ARCHIVE_FAILED path=${archive_path}"
  fi
else
  log_event "ARCHIVE_SKIPPED reason=no_tar"
fi

# ---------------------------------------------------------------------
# Hashing (archive or directory)
# ---------------------------------------------------------------------

if [ "${HASH_AVAILABLE:-0}" -eq 1 ]; then

  run_hash() {
    local source_path="$1"
    local output_path="$2"

    if "${HASH_CMD}" "${source_path}" >"${output_path}" 2>>"${LOG_FILE}"; then
      log_event "HASH_CREATED file=${output_path}"
    else
      log_event "HASH_FAILED file=${source_path}"
    fi
  }

  if [ "${ARCHIVE_CREATED}" -eq 1 ]; then
    run_hash "${archive_path}" "${archive_path}.${HASH_CMD}"
  else
    if find "${OUTPUT_ROOT}" -type f -exec "${HASH_CMD}" {} + >"${OUTPUT_ROOT}.hashes.${HASH_CMD}" 2>>"${LOG_FILE}"; then
      log_event "HASH_CREATED directory=${OUTPUT_ROOT}.hashes.${HASH_CMD}"
    else
      log_event "HASH_FAILED directory=${OUTPUT_ROOT}"
    fi
  fi

  # -----------------------------------------------------------------
  # Final log entries BEFORE hashing log
  # -----------------------------------------------------------------

  log_event "EVIDENCE_LOCATION path=${OUTPUT_ROOT}"
  log_event "HASHING log_file=${LOG_FILE}"

  # -----------------------------------------------------------------
  # FINAL STEP: hash log (no writes after this)
  # -----------------------------------------------------------------

  "${HASH_CMD}" "${LOG_FILE}" >"${LOG_FILE}.${HASH_CMD}" 2>/dev/null || true

else
  log_event "HASH_SKIPPED reason=no_hash_tool"
  log_event "EVIDENCE_LOCATION path=${OUTPUT_ROOT}"
fi


# SCRIPT GENERATION METADATA
# Generated acquisition script
# Timestamp: 2026-03-21T12:39:14.108157400+00:00
# Profile used: ALPINE.STANDARD.V1
# Profile location: ./profiles/apline-standard-profile.yml
# Task List Location: ./tasks/

