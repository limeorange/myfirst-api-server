#!/bin/bash

# 템플릿 변수 치환 스크립트
# env.properties 파일의 KEY=VALUE를 사용하여 .t / .j 파일들의 {{KEY}} 형태 변수를 치환
# .t 파일 -> 확장자를 .yaml로 변경한 결과 파일 생성
# .j 파일 -> 확장자를 제거한 결과 파일 생성
# macOS와 Ubuntu 모두 호환

set -e  # 에러 발생 시 스크립트 종료

# 색상 코드 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEMP_FILE=$(mktemp)
ERROR_COUNT=0

# 변수 초기화
PROPERTIES_PATH=""  # env.properties를 찾을 경로
PROPERTIES_FILE=""  # 최종 env.properties 파일 경로
TEMPLATE_DIR="."    # *.t, *.j 파일을 찾을 디렉토리 (항상 현재 디렉토리 + 하위)
COMMAND="create"

# 사용법 표시 함수
show_usage() {
    echo -e "${BLUE}사용법:${NC}"
    echo -e "  $0 [옵션] [명령어]"
    echo ""
    echo -e "${BLUE}옵션:${NC}"
    echo -e "  -f <파일>            env.properties 파일 경로 지정"
    echo ""
    echo -e "${BLUE}경로 인수:${NC}"
    echo -e "  (없음)               현재 디렉토리의 env.properties 사용 (기본값)"
    echo -e "  .. 또는 ../          상위 디렉토리의 env.properties 사용"
    echo -e "  ../.. 또는 ../../    두 단계 상위 디렉토리의 env.properties 사용"
    echo -e "  ../../.. 또는 ../../../   세 단계 상위 디렉토리의 env.properties 사용"
    echo ""
    echo -e "${BLUE}명령어:${NC}"
    echo -e "  create               결과 파일 생성 (기본값)"
    echo -e "  delete, rm           생성된 결과 파일 삭제 (.generated 파일 기준)"
    echo -e "  help                 도움말 표시"
    echo ""
    echo -e "${BLUE}예시:${NC}"
    echo -e "  $0                          # 현재 디렉토리의 env.properties 사용"
    echo -e "  $0 ..                       # 상위 디렉토리의 env.properties 사용"
    echo -e "  $0 ../..                    # 두 단계 상위 디렉토리의 env.properties 사용"
    echo -e "  $0 ../../..                 # 세 단계 상위 디렉토리의 env.properties 사용"
    echo -e "  $0 -f ../env.properties     # 지정된 env.properties 파일 사용"
    echo -e "  $0 .. delete                # 상위 디렉토리 properties로 생성된 결과 파일 삭제"
    echo -e "  $0 -f env.dev.properties    # 다른 이름의 properties 파일 사용"
    echo ""
    echo -e "${BLUE}주의:${NC}"
    echo -e "  - *.t, *.j 파일은 항상 현재 디렉토리와 모든 하위 디렉토리에서 찾습니다"
    echo -e "  - *.t 파일은 \${파일명}.yaml 로, *.j 파일은 확장자를 제거한 파일명으로 결과가 생성됩니다"
    echo -e "  - 템플릿 파일의 변수는 {{KEY}} 형태로 작성합니다"
    echo -e "  - env.properties의 위치만 지정할 수 있습니다"
    echo -e "  - create 시 .t/.j 파일과 같은 디렉토리에 .generated 파일을 생성하여 결과 파일명을 기록합니다"
    echo -e "  - delete(rm) 시 .generated 에 기록된 파일을 삭제하고 .generated 파일도 함께 삭제합니다"
}

# 인수 파싱
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v | --version)
            echo "2026.08.01 v3.3"
            exit 1
            ;;
        -f)
            if [ -z "$2" ]; then
                echo -e "${RED}오류: -f 옵션에는 파일 경로가 필요합니다${NC}"
                show_usage
                exit 1
            fi
            PROPERTIES_FILE="$2"
            shift 2
            ;;
        help)
            show_usage
            exit 0
            ;;
        create|delete)
            COMMAND="$1"
            shift
            ;;
        rm)
            # delete 명령어의 별칭
            COMMAND="delete"
            shift
            ;;
        .)
            PROPERTIES_PATH="."
            shift
            ;;
        ..)
            PROPERTIES_PATH=".."
            shift
            ;;
        ../)
            PROPERTIES_PATH=".."
            shift
            ;;
        ../../)
            PROPERTIES_PATH="../.."
            shift
            ;;
        ../../*)
            # ../../ 로 시작하는 경로 처리
            PROPERTIES_PATH="$1"
            shift
            ;;
        ../*)
            # ../ 로 시작하는 경로 처리
            PROPERTIES_PATH="$1"
            shift
            ;;
        *)
            echo -e "${RED}오류: 알 수 없는 인수입니다: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# env.properties 파일 경로 결정
if [ -n "$PROPERTIES_FILE" ]; then
    # -f 옵션으로 파일이 직접 지정된 경우
    if [ ! -f "$PROPERTIES_FILE" ]; then
        echo -e "${RED}오류: 지정된 파일을 찾을 수 없습니다: $PROPERTIES_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}env.properties 파일: $PROPERTIES_FILE (직접 지정)${NC}"
else
    # 경로 인수가 없으면 기본값: 현재 디렉토리
    if [ -z "$PROPERTIES_PATH" ]; then
        PROPERTIES_PATH="."
    fi

    PROPERTIES_FILE="$PROPERTIES_PATH/env.properties"

    if [ ! -f "$PROPERTIES_FILE" ]; then
        echo -e "${RED}오류: $PROPERTIES_FILE 파일을 찾을 수 없습니다.${NC}"
        exit 1
    fi

    # 경로 표시
    if [ "$PROPERTIES_PATH" = "." ]; then
        echo -e "${GREEN}env.properties 파일: ./env.properties (현재 디렉토리)${NC}"
    else
        echo -e "${GREEN}env.properties 파일: $PROPERTIES_FILE (상위 디렉토리)${NC}"
    fi
fi

echo -e "${GREEN}=== 템플릿 스크립트 ($COMMAND 모드) ===${NC}"

# .t, .j 확장자 파일들 찾기 (현재 디렉토리 + 모든 하위 디렉토리)
echo -e "${YELLOW}1. 현재 디렉토리 및 하위 디렉토리에서 .t, .j 확장자 파일 검색 중...${NC}"

template_files_array=()
while IFS= read -r file; do
    template_files_array+=("$file")
done < <(find "$TEMPLATE_DIR" -type f \( -name "*.t" -o -name "*.j" \) 2>/dev/null)

if [ ${#template_files_array[@]} -eq 0 ]; then
    echo -e "${RED}오류: 현재 디렉토리 및 하위 디렉토리에서 .t, .j 확장자 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}발견된 템플릿 파일 개수: ${#template_files_array[@]}${NC}"
for file in "${template_files_array[@]}"; do
    echo "  - $file"
done

# 함수: 템플릿 파일 확장자에 따른 결과 파일 경로 계산
# .t -> 확장자를 .yaml로 변경, .j -> 확장자 제거
get_output_file() {
    local file="$1"
    if [[ "$file" == *.t ]]; then
        echo "${file%.t}.yaml"
    elif [[ "$file" == *.j ]]; then
        echo "${file%.j}"
    fi
}

# DELETE 모드 처리
if [ "$COMMAND" = "delete" ]; then
    echo -e "${YELLOW}2. .generated 파일 기반으로 결과 파일 삭제 중...${NC}"

    generated_files_array=()
    while IFS= read -r file; do
        generated_files_array+=("$file")
    done < <(find "$TEMPLATE_DIR" -type f -name ".generated" 2>/dev/null)

    if [ ${#generated_files_array[@]} -eq 0 ]; then
        echo -e "${YELLOW}   삭제할 .generated 파일이 없습니다.${NC}"
    fi

    for gen_file in "${generated_files_array[@]}"; do
        dir=$(dirname "$gen_file")

        while IFS= read -r name || [[ -n "$name" ]]; do
            [ -z "$name" ] && continue
            target="$dir/$name"
            if [ -f "$target" ]; then
                rm -f "$target"
                echo -e "${GREEN}   삭제됨: $target${NC}"
            fi
        done < "$gen_file"

        rm -f "$gen_file"
        echo -e "${GREEN}   삭제됨: $gen_file${NC}"
    done

    echo -e "${GREEN}=== 결과 파일 삭제 완료 ===${NC}"
    rm -f "$TEMP_FILE"
    exit 0
fi

# CREATE 모드 - env.properties 파일 로드
echo -e "${YELLOW}2. $PROPERTIES_FILE 파일에서 변수 로드 중...${NC}"

# properties 파일 로드를 위한 임시 파일
VARS_FILE=$(mktemp)

# properties 파일을 읽고 변수 저장
while IFS= read -r line || [[ -n "$line" ]]; do
    # Windows CR 문자 제거 (WSL 호환)
    line="${line//$'\r'/}"

    # 주석이나 빈 줄 건너뛰기
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" != *"="* ]] && continue

    # key=value 분리 (macOS와 Ubuntu 모두 호환)
    key=$(echo "$line" | cut -d '=' -f 1 | xargs)
    value=$(echo "$line" | cut -d '=' -f 2- | xargs)

    # 따옴표 제거
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"

    # value에 ${환경변수명} 형태가 있으면 실제 환경 변수 값으로 치환
    # 해당 환경 변수가 선언되어 있지 않으면 오류 출력 후 스크립트 중단
    while [[ "$value" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        env_var_name="${BASH_REMATCH[1]}"
        if [ -z "${!env_var_name+x}" ]; then
            echo -e "${RED}오류: $PROPERTIES_FILE 의 '$key' 값에서 참조하는 환경 변수 '\${$env_var_name}'가 선언되어 있지 않습니다.${NC}"
            rm -f "$TEMP_FILE" "$VARS_FILE"
            exit 1
        fi
        env_var_value="${!env_var_name}"
        value="${value//\$\{$env_var_name\}/$env_var_value}"
    done

    # 유효한 key-value만 저장
    if [[ -n "$key" && -n "$value" ]]; then
        echo "$key=$value" >> "$VARS_FILE"
        echo "  - $key = $value"
    fi
done < "$PROPERTIES_FILE"

# HASHCODE 자동 생성
GENERATED_HASHCODE=$(date +%s | shasum | cut -c1-8)  # macOS는 shasum 사용
echo "HASHCODE=$GENERATED_HASHCODE" >> "$VARS_FILE"
echo "  - HASHCODE = $GENERATED_HASHCODE (자동 생성)"

echo -e "${GREEN}변수 로드 완료${NC}"

# 변수가 제대로 로드되었는지 확인
if [[ ! -s "$VARS_FILE" ]]; then
    echo -e "${RED}오류: properties 파일에서 변수를 로드하지 못했습니다.${NC}"
    echo -e "${YELLOW}파일 내용 확인:${NC}"
    cat "$PROPERTIES_FILE" | head -10
    rm -f "$TEMP_FILE" "$VARS_FILE"
    exit 1
fi

echo -e "${YELLOW}3. 템플릿 파일 처리 중...${NC}"

# 함수: 파일에서 모든 {{변수명}} 패턴 추출
extract_variables() {
    local file="$1"
    grep -o '{{[A-Za-z_][A-Za-z0-9_]*}}' "$file" 2>/dev/null | sed 's/{{//;s/}}//' | sort -u
}

# 함수: 변수 값 가져오기
get_variable_value() {
    local var_name="$1"
    grep "^$var_name=" "$VARS_FILE" 2>/dev/null | cut -d'=' -f2-
}

# 함수: 변수 확인
check_variables() {
    local file="$1"
    local missing_vars=()
    local vars=$(extract_variables "$file")

    if [ -n "$vars" ]; then
        echo "  검증 중: $file"
        for var in $vars; do
            local value=$(get_variable_value "$var")
            if [ -z "$value" ]; then
                missing_vars+=("$var")
                echo -e "    ${RED}✗ {{$var}} - 정의되지 않음${NC}"
                ((ERROR_COUNT++))
            fi
        done

        if [ ${#missing_vars[@]} -gt 0 ]; then
            return 1
        fi
    fi
    return 0
}

# 함수: 파일의 변수 치환
replace_variables() {
    local file="$1"
    local output_file
    output_file=$(get_output_file "$file")

    # 파일 복사 (CR 제거)
    tr -d '\r' < "$file" > "$TEMP_FILE"

    # 변수 치환
    while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            # 특수문자 이스케이프 (macOS sed 호환)
            escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{\\]/\\&/g')

            # macOS와 Linux 모두 호환되는 sed 사용
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                sed -i '' "s|{{$key}}|$escaped_value|g" "$TEMP_FILE"
            else
                # Linux
                sed -i "s|{{$key}}|$escaped_value|g" "$TEMP_FILE"
            fi
        fi
    done < "$VARS_FILE"

    # 결과 저장
    cp "$TEMP_FILE" "$output_file"
    echo -e "${GREEN}   ✓ $file -> $output_file${NC}"

    # .generated 파일에 생성된 결과 파일명 기록 (.t/.j 파일과 같은 디렉토리에 저장)
    local dir
    dir=$(dirname "$file")
    basename "$output_file" >> "$dir/.generated"
}

# 변수 검증
echo -e "${YELLOW}변수 검증 중...${NC}"
for file in "${template_files_array[@]}"; do
    if [ -f "$file" ]; then
        check_variables "$file"
    fi
done

# 오류 확인
if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "${RED}오류: 총 $ERROR_COUNT 개의 정의되지 않은 변수가 발견되었습니다.${NC}"
    rm -f "$TEMP_FILE" "$VARS_FILE"
    exit 1
fi

# .t/.j 파일이 위치한 디렉토리별로 .generated 파일 초기화
generated_dirs=()
for file in "${template_files_array[@]}"; do
    dir=$(dirname "$file")
    already_seen=false
    for gd in "${generated_dirs[@]}"; do
        if [ "$gd" = "$dir" ]; then
            already_seen=true
            break
        fi
    done
    if [ "$already_seen" = false ]; then
        generated_dirs+=("$dir")
        : > "$dir/.generated"
    fi
done

# 변수 치환 수행
echo -e "${YELLOW}변수 치환 수행 중...${NC}"
for file in "${template_files_array[@]}"; do
    if [ -f "$file" ]; then
        replace_variables "$file"
    fi
done

# 정리
rm -f "$TEMP_FILE" "$VARS_FILE"

echo -e "${GREEN}=== 템플릿 결과 파일 생성 완료 ===${NC}"
echo -e "${GREEN}${#template_files_array[@]}개의 .t/.j 파일이 성공적으로 변환되었습니다.${NC}"
