#!/bin/bash

# 彩色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 错误捕捉
error_exit() {
    echo -e "${RED}发生错误: 第${1}行, 命令: ${2}${NC}"
    exit 1
}
trap 'error_exit ${LINENO} "$BASH_COMMAND"' ERR

# 防止僵尸进程
trap 'jobs -p | xargs -r kill' EXIT

# Harbor配置
HARBOR_URL="192.168.26.99"
HARBOR_USER="benboerba"
HARBOR_PASSWORD="hB@sY#Lov1"

# 登录Harbor
login_harbor() {
    echo "${HARBOR_PASSWORD}" | docker login -u "${HARBOR_USER}" --password-stdin "${HARBOR_URL}" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Harbor登录失败，请检查用户名和密码！${NC}"
        exit 1
    fi
}

# 获取harbor上的所有项目
get_projects() {
    curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
        "https://${HARBOR_URL}/api/v2.0/projects" \
        | jq -r '.[] | [.name, .creation_time] | @tsv'
}

# 查看所有项目
show_all_projects() {
    local PROJECTS
    PROJECTS=$(get_projects)
    echo -e "${GREEN}================= Harbor 项目列表 =================${NC}"
    echo -e "ID\t项目名\t创建时间"
    local i=1
    while IFS=$'\t' read -r name ctime; do
        echo -e "$i\t$name\t$ctime"
        ((i++))
    done <<< "${PROJECTS}"
    echo -e "${GREEN}===================================================${NC}"
    read -p "请输入要查看镜像列表的项目ID(或回车返回菜单): " PID
    if [[ -z "$PID" ]]; then
        return
    fi
    local pname=$(echo "${PROJECTS}" | awk "NR==$PID{print \$1}")
    if [[ -z "$pname" ]]; then
        echo -e "${RED}项目ID无效！${NC}"
        return
    fi
    show_project_images "$pname"
}

# 查看指定项目下镜像列表
show_project_images() {
    local PROJECT_NAME="$1"
    echo -e "${YELLOW}仓库 ${PROJECT_NAME} 下的镜像列表:${NC}"
    local repos
    repos=$(curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
        "https://${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/repositories" \
        | jq -r '.[] | .name')
    for repo in $repos; do
        echo -e "${BLUE}镜像: $repo${NC}"
        curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
            "https://${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/repositories/${repo//\//%2F}/artifacts" \
            | jq -r '
                if type=="array" then
                  .[]
                else
                  .
                end
                | if (.tags and (.tags|type=="array") and (.tags|length>0)) then
                    "  标签: " + (.tags[]?.name // "无")
                  else
                    "  标签: 无"
                  end
            ' || { echo -e "${RED}解析镜像标签时发生错误！${NC}"; exit 1; }
    done
}

# 查看本地所有镜像
show_local_images() {
    echo -e "${GREEN}本地所有镜像:${NC}"
    printf "%-4s %-40s %-20s %-20s %-10s\n" "序号" "REPOSITORY" "TAG" "IMAGE_ID" "SIZE"
    docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' | \
    awk -F'\t' '{printf "%-4s %-40s %-20s %-20s %-10s\n", NR, $1, $2, $3, $4}'
}

# 查看指定镜像（模糊匹配）
search_local_image() {
    read -p "请输入镜像名称关键字: " IMAGE_FILTER
    if [[ -z "${IMAGE_FILTER}" ]]; then
        echo -e "${RED}关键字不能为空！${NC}"
        return
    fi
    local IMAGES
    IMAGES=$(docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' | grep "${IMAGE_FILTER}")
    if [[ -z "${IMAGES}" ]]; then
        echo -e "${RED}没有找到相关镜像！${NC}"
        return
    fi
    echo -e "${GREEN}匹配到以下镜像:${NC}"
    printf "%-4s %-40s %-20s %-20s %-10s\n" "ID" "REPOSITORY" "TAG" "IMAGE_ID" "SIZE"
    local i=1
    select_line=()
    while IFS=$'\n' read -r line; do
        REPO=$(echo -e "${line}" | awk '{print $1}')
        TAG=$(echo -e "${line}" | awk '{print $2}')
        IMAGE_ID=$(echo -e "${line}" | awk '{print $3}')
        SIZE=$(echo -e "${line}" | awk '{print $4}')
        printf "%-4s %-40s %-20s %-20s %-10s\n" "$i" "$REPO" "$TAG" "$IMAGE_ID" "$SIZE"
        select_line+=("${line}")
        ((i++))
    done <<< "${IMAGES}"

    read -p "请输入要推送的镜像ID: " IMAGE_INDEX
    if ! [[ "$IMAGE_INDEX" =~ ^[0-9]+$ ]] || (( IMAGE_INDEX < 1 || IMAGE_INDEX > ${#select_line[@]} )); then
        echo -e "${RED}镜像ID无效！${NC}"
        return
    fi
    CHOSEN="${select_line[$((IMAGE_INDEX - 1))]}"
    REPO=$(echo -e "${CHOSEN}" | awk '{print $1}')
    TAG=$(echo -e "${CHOSEN}" | awk '{print $2}')
    IMAGE_ID=$(echo -e "${CHOSEN}" | awk '{print $3}')

    # 显示可推送的仓库
    local PROJECTS
    PROJECTS=$(get_projects)
    echo -e "${GREEN}可推送的仓库列表:${NC}"
    echo -e "ID\t项目名"
    local j=1
    while IFS=$'\t' read -r name ctime; do
        echo -e "$j\t$name"
        ((j++))
    done <<< "${PROJECTS}"
    read -p "请输入目标仓库ID: " PID
    local PROJECT_NAME=$(echo "${PROJECTS}" | awk "NR==$PID{print \$1}")
    if [[ -z "$PROJECT_NAME" ]]; then
        echo -e "${RED}仓库ID无效！${NC}"
        return
    fi

    # 处理无标签镜像
    if [[ "$TAG" == "<none>" ]]; then
        read -p "该镜像未打tag，请输入新的标签: " NEW_TAG
        if [[ -z "${NEW_TAG}" ]]; then
            echo -e "${RED}标签不能为空！${NC}"
            return
        fi
        IMAGE_BASENAME=$(basename "$REPO")
        HARBOR_REPO="${HARBOR_URL}/${PROJECT_NAME}/${IMAGE_BASENAME}"
        TAG="${NEW_TAG}"
        docker tag "${IMAGE_ID}" "${REPO}:${TAG}"
    fi

    # 目标 Harbor 镜像名
    IMAGE_BASENAME=$(basename "$REPO")
    HARBOR_REPO="${HARBOR_URL}/${PROJECT_NAME}/${IMAGE_BASENAME}"

    # 判断是否已是 Harbor 项目格式
    if [[ "$REPO" != "${HARBOR_URL}/${PROJECT_NAME}/"* ]]; then
        echo -e "${YELLOW}镜像未打 Harbor 项目标签，正在打标签：${HARBOR_REPO}:${TAG}${NC}"
        docker tag "${IMAGE_ID}" "${HARBOR_REPO}:${TAG}"
    else
        HARBOR_REPO="$REPO"
    fi

    # 推送镜像
    echo -e "${YELLOW}正在推送镜像：${HARBOR_REPO}:${TAG}...${NC}"
    docker push "${HARBOR_REPO}:${TAG}"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}镜像推送失败，请检查网络或Harbor配置！${NC}"
    else
        echo -e "${GREEN}镜像 ${HARBOR_REPO}:${TAG} 推送成功！${NC}"
    fi
}

# 推送镜像到指定仓库
push_image_to_project() {
    local PROJECTS
    PROJECTS=$(get_projects)
    echo -e "${GREEN}请选择目标项目:${NC}"
    echo -e "ID\t项目名\t创建时间"
    local i=1
    while IFS=$'\t' read -r name ctime; do
        echo -e "$i\t$name\t$ctime"
        ((i++))
    done <<< "${PROJECTS}"
    read -p "请输入目标项目ID: " PID
    local PROJECT_NAME=$(echo "${PROJECTS}" | awk "NR==$PID{print \$1}")
    if [[ -z "$PROJECT_NAME" ]]; then
        echo -e "${RED}项目ID无效！${NC}"
        return
    fi

    # 选择本地镜像
    local IMAGES=$(docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}')
    if [[ -z "${IMAGES}" ]]; then
        echo -e "${RED}本地没有可用镜像！${NC}"
        return
    fi
    echo -e "${GREEN}本地镜像列表:${NC}"
    printf "%-4s %-40s %-20s %-20s %-10s\n" "序号" "REPOSITORY" "TAG" "IMAGE_ID" "SIZE"
    local i=1
    select_line=()
    while IFS=$'\n' read -r line; do
        REPO=$(echo -e "${line}" | awk '{print $1}')
        TAG=$(echo -e "${line}" | awk '{print $2}')
        IMAGE_ID=$(echo -e "${line}" | awk '{print $3}')
        SIZE=$(echo -e "${line}" | awk '{print $4}')
        printf "%-4s %-40s %-20s %-20s %-10s\n" "$i" "$REPO" "$TAG" "$IMAGE_ID" "$SIZE"
        select_line+=("${line}")
        ((i++))
    done <<< "${IMAGES}"

    read -p "请输入要推送的镜像序号: " IMAGE_INDEX
    CHOSEN="${select_line[$((IMAGE_INDEX - 1))]}"
    REPO=$(echo -e "${CHOSEN}" | awk '{print $1}')
    TAG=$(echo -e "${CHOSEN}" | awk '{print $2}')
    IMAGE_ID=$(echo -e "${CHOSEN}" | awk '{print $3}')

    # 处理无标签镜像
    if [[ "$TAG" == "<none>" ]]; then
        read -p "该镜像未打tag，请输入新的标签: " NEW_TAG
        if [[ -z "${NEW_TAG}" ]]; then
            echo -e "${RED}标签不能为空！${NC}"
            return
        fi
        IMAGE_BASENAME=$(basename "$REPO")
        HARBOR_REPO="${HARBOR_URL}/${PROJECT_NAME}/${IMAGE_BASENAME}"
        TAG="${NEW_TAG}"
        docker tag "${IMAGE_ID}" "${REPO}:${TAG}"
    fi

    # 目标 Harbor 镜像名
    IMAGE_BASENAME=$(basename "$REPO")
    HARBOR_REPO="${HARBOR_URL}/${PROJECT_NAME}/${IMAGE_BASENAME}"

    # 判断是否已是 Harbor 项目格式
    if [[ "$REPO" != "${HARBOR_URL}/${PROJECT_NAME}/"* ]]; then
        echo -e "${YELLOW}镜像未打 Harbor 项目标签，正在打标签：${HARBOR_REPO}:${TAG}${NC}"
        docker tag "${IMAGE_ID}" "${HARBOR_REPO}:${TAG}"
    else
        HARBOR_REPO="$REPO"
    fi

    # 推送镜像
    echo -e "${YELLOW}正在推送镜像：${HARBOR_REPO}:${TAG}...${NC}"
    docker push "${HARBOR_REPO}:${TAG}"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}镜像推送失败，请检查网络或Harbor配置！${NC}"
        return
    else
        echo -e "${GREEN}镜像 ${HARBOR_REPO}:${TAG} 推送成功！${NC}"
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "${GREEN}\n========= Harbor 镜像管理菜单 ========="
        echo "1、查看所有项目(输入项目ID即可查看该项目下镜像列表)"
        echo "2、查看本地所有镜像"
        echo "3、查看指定镜像(输入镜像名即可模糊匹配)"
        echo "4、推送镜像到指定仓库"
        echo "5、退出"
        echo "======================================${NC}"
        read -p "请输入选项(1-5): " CHOICE
        case "$CHOICE" in
            1) show_all_projects ;;
            2) show_local_images ;;
            3) search_local_image ;;
            4) push_image_to_project ;;
            5) echo -e "${GREEN}感谢使用镜像管理脚本！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项，请重新输入！${NC}" ;;
        esac
    done
}

# 主流程
login_harbor
main_menu