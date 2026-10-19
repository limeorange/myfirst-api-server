#!/usr/bin/env bash

# KEY=VALUE 파일을 읽어 환경변수로 export; ${VAR} 참조도 현재 환경변수로 확장
load_properties() {
  local props_file="${1:-../env.properties}"

  if [[ ! -f "${props_file}" ]]; then
    echo "환경 파일을 찾을 수 없습니다: ${props_file}" >&2
    exit 1
  fi

  while IFS='=' read -r key value; do
    key=$(printf '%s' "${key}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "${key}" in
      ''|'#'*) continue ;;
    esac
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "잘못된 환경 변수 이름: ${key}" >&2
      exit 1
    fi
    value=$(printf '%s' "${value}" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | envsubst)
    export "${key}=${value}"
  done < "${props_file}"
}
