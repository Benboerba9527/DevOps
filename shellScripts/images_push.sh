#!/bin/bash

# Author: Benboerba
# Date: 2025-05-14 12:19:08
# Description: 自动化推送镜像到 Harbor

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误捕捉
error_exit() {
    local lineno=$1
    local msg=$2
    echo -e "${RED}发生错误: 第${lineno}行,命令:${msg}${NC}"
    exit 1
}
trap 'error_exit ${LINENO} "$BASH_COMMAND"' ERR

# Harbor配置
HARBOR_URL="192.168.26.99"
HARBOR_USER="benboerba"
HARBOR_PASSWORD="hB@sY#Lov1"

# 登录Harbor
login_harbor() {
    echo -e "${YELLOW}正在登录Harbor...${NC}"
    echo "${HARBOR_PASSWORD}" | docker login -u "${HARBOR_USER}" --password-stdin "${HARBOR_URL}" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}登录失败，请检查用户名和密码！${NC}"
        exit 1
    else
        echo -e "${GREEN}Harbor登陆成功!${NC}"
    fi
}

# 获取harbor上的所有项目
get_projects() {
    PROJECTS=$(curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
        "https://${HARBOR_URL}/api/v2.0/projects" \
        | jq -r '.[] | [.name, .creation_time] | @tsv')
}

# 推送镜像
push_image() {
    local PROJECT_NAME="$1"

    # 镜像显示方式选择
    echo -e "${YELLOW}请选择镜像显示方式：${NC}"
    echo "1. 显示所有本地镜像"
    echo "2. 根据关键字模糊匹配"
    read -p "请输入选项(1/2): " IMAGE_MODE

    if [[ "${IMAGE_MODE}" == "1" ]]; then
        IMAGE_FILTER=""
    else
        read -p "请输入要推送的镜像名称(可使用模糊匹配): " IMAGE_FILTER
    fi

    # 获取本地所有匹配镜像
    if [[ -z "${IMAGE_FILTER}" ]]; then
        IMAGES=$(docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}')
    else
        IMAGES=$(docker images --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' | grep "${IMAGE_FILTER}")
    fi

    if [[ -z "${IMAGES}" ]]; then
        echo -e "${RED}没有找到相关镜像，请检查镜像名称！${NC}"
        exit 1
    fi

    # 显示带序号的镜像列表
    echo -e "${GREEN}找到以下相关镜像:${NC}"
    #echo -e "序号\tREPOSITORY\tTAG\tIMAGE ID\tSIZE"
    # 对齐优化修改
    #printf "序号\tREPOSITORY\tTAG\tIMAGE_ID\tSIZE\n"
    printf "%-4s %-40s %-20s %-20s %-10s\n" "序号" "REPOSITORY" "TAG" "IMAGE_ID" "SIZE"
    IFS=$'\n'
    select_line=()
    i=1
    for line in ${IMAGES}; do
        REPO=$(echo -e "${line}" | awk '{print $1}')
        TAG=$(echo -e "${line}" | awk '{print $2}')
        IMAGE_ID=$(echo -e "${line}" | awk '{print $3}')
        SIZE=$(echo -e "${line}" | awk '{print $4}')
        printf "%-4s %-40s %-20s %-20s %-10s\n" "$i" "$REPO" "$TAG" "$IMAGE_ID" "$SIZE"
        select_line+=("${line}")
        ((i++))
    done
    unset IFS

    # 用户选择镜像
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
            exit 1
        fi
        # 目标Harbor镜像名
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
        exit 1
    else
        echo -e "${GREEN}镜像 ${HARBOR_REPO}:${TAG} 推送成功！${NC}"
    fi


    # 是否查看该仓库下镜像列表
    read -p "是否查看该仓库下的镜像列表？(y/n): " VIEW_IMAGES
    if [[ "${VIEW_IMAGES}" == "y" || "${VIEW_IMAGES}" == "Y" ]]; then
        echo -e "${YELLOW}仓库 ${PROJECT_NAME} 下的镜像列表:${NC}"
        curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
            "https://${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/repositories" \
            | jq -r '.[] | .name' | while read repo; do
                echo -e "${BLUE}镜像: $repo${NC}"
                curl -sk -u "${HARBOR_USER}:${HARBOR_PASSWORD}" \
                    "https://${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/repositories/${repo//\//%2F}/artifacts" \
                    | jq -r '.[] | "  标签: " + (.tags[]?.name // "无")'
            done
    fi

    # 是否继续
    read -p "是否继续推送其他镜像？(y/n): " CONTINUE
    if [[ "${CONTINUE}" == "y" || "${CONTINUE}" == "Y" ]]; then
        push_image "${PROJECT_NAME}"
    else
        echo -e "${GREEN}感谢使用镜像推送脚本！${NC}"
        exit 0
    fi
}

# 菜单
show_menu() {
    echo -e "${BLUE}================= Harbor 项目列表 =================${NC}"
    get_projects
    echo -e "${YELLOW}请选择要推送的项目:${NC}"
    echo -e "项目名\t创建时间"
    echo "${PROJECTS}" | column -t
    echo -e "${BLUE}=====================================================${NC}"

    # 校验项目名输入
    while true; do
        read -p "请输入项目名称: " PROJECT_NAME
        if [[ -z "${PROJECT_NAME}" ]]; then
            echo -e "${RED}项目名称不能为空！请重新输入项目名！${NC}"
            continue
        fi
        # 校验输入的项目名是否在PROJECTS中
        if ! echo "${PROJECTS}" | awk '{print $1}' | grep -wq "${PROJECT_NAME}"; then
            echo -e "${RED}项目名称不存在，请按上表输入正确的项目名！${NC}"
            continue
        fi
        echo -e "${GREEN}您选择的项目是: ${PROJECT_NAME}${NC}"
        break
    done

    push_image "${PROJECT_NAME}"
}

# 主流程
login_harbor
show_menu