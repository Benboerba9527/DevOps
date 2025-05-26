#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
File: family_ordering_mini_program.py
Author: Benboerba
Email: benboerba_9527@163.com
Created: 2025-05-19
"""

"""
V3.0: 使用PaddleOCR官方PPStructureV3自动还原表格结构，将食谱图片内容写入Xlsx表格
"""
import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""
import sys
sys.path.insert(0, "/opt/DevOps/PaddleOCR")  # 如已pip安装可去掉

import glob
from paddleocr import PPStructureV3

def get_latest_image(directory, exts=('jpg', 'jpeg', 'png')):
    """
    获取目录下最新的图片文件路径
    :param directory: 图片目录
    :param exts: 支持的图片扩展名
    :return: 最新图片的完整路径或None
    """
    files = []
    for ext in exts:
        files.extend(glob.glob(os.path.join(directory, f'*.{ext}')))
    if not files:
        return None
    latest_file = max(files, key=os.path.getmtime)
    return latest_file

def extract_table_to_excel(image_path, output_dir):
    """
    使用PPStructureV3提取表格并保存为Excel
    :param image_path: 输入图片路径
    :param output_dir: 输出目录
    """
    try:
        os.makedirs(output_dir, exist_ok=True)
        # 初始化结构化表格识别器
        table_engine = PPStructureV3()
        # 调用时传递output_dir参数
        result = table_engine(image_path, output_dir=output_dir)
        print(f"结构化表格Excel已输出到: {output_dir}")
    except Exception as e:
        print(f"OCR结构化表格处理失败: {e}")

if __name__ == "__main__":
    # 主程序入口：查找最新图片并执行结构化表格识别
    base_dir = "/opt/DevOps/pythonScripts/food_menu_images"
    output_dir = os.path.join(base_dir, "ppstructure_output")
    latest_image = get_latest_image(base_dir)
    if not latest_image:
        print("未找到图片文件，请检查目录！")
        exit(1)
    extract_table_to_excel(latest_image, output_dir)