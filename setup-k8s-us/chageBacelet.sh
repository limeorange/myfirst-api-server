#!/bin/bash

# .t 파일 변수 표기 변경 스크립트
# 현재 디렉토리 및 모든 하위 디렉토리의 .t 파일에서 ${KEY} 형태를 {{KEY}} 형태로 변경
# macOS 전용 (BSD sed 기준)

set -e  # 에러 발생 시 스크립트 종료

# 색상 코드 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TARGET_DIR="."

echo -e "${YELLOW}현재 디렉토리 및 하위 디렉토리에서 .t 확장자 파일 검색 중...${NC}"

t_files_array=()
while IFS= read -r file; do
    t_files_array+=("$file")
done < <(find "$TARGET_DIR" -type f -name "*.t" 2>/dev/null)

if [ ${#t_files_array[@]} -eq 0 ]; then
    echo -e "${RED}오류: .t 확장자 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}발견된 .t 파일 개수: ${#t_files_array[@]}${NC}"

CHANGED_COUNT=0

for file in "${t_files_array[@]}"; do
    # 변경 대상(${VAR}) 존재 여부 확인
    if grep -q '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null; then
        # BSD sed(macOS)는 -i 뒤에 빈 문자열 백업 확장자가 필요함
        sed -E -i '' 's/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/{{\1}}/g' "$file"
        echo -e "${GREEN}   변경됨: $file${NC}"
        CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
done

echo -e "${GREEN}=== 변경 완료: ${CHANGED_COUNT}개 파일의 \${KEY} -> {{KEY}} 변환 완료 ===${NC}"
