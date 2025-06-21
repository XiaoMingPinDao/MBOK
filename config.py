import os
import shutil
import yaml  # 导入新的库
from datetime import datetime

# --- 配置项 ---
PROJECT_ROOT = '.'
RUN_DIR = os.path.join(PROJECT_ROOT, 'run')
BACKUP_DIR = os.path.join(PROJECT_ROOT, 'backups')
# 使用 .yaml 作为中央配置文件的扩展名
TARGET_YAML_BUNDLE_FILE = os.path.join(PROJECT_ROOT, 'eridanus_configs_bundle.yaml') 
# --- 配置项结束 ---

def ensure_dir_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)
        print(f"✅ 已创建目录: {path}")

def find_yaml_files():
    if not os.path.isdir(RUN_DIR):
        print(f"❌ 错误: '{RUN_DIR}' 目录未找到。请在 Eridanus 项目根目录下运行脚本。")
        return []
    yaml_files = []
    for root, dirs, files in os.walk(RUN_DIR):
        for file in files:
            if file.endswith(('.yaml', '.yml')):
                yaml_files.append(os.path.join(root, file))
    print(f"🔍 在 '{RUN_DIR}' 及其子目录中递归查找到 {len(yaml_files)} 个 YAML 配置文件。")
    return yaml_files

def backup_file(file_path):
    ensure_dir_exists(BACKUP_DIR)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    relative_path = os.path.relpath(file_path, PROJECT_ROOT)
    safe_filename = relative_path.replace(os.sep, '_')
    backup_path = os.path.join(BACKUP_DIR, f"{safe_filename}.{timestamp}.bak")
    try:
        shutil.copy(file_path, backup_path)
        print(f"🛡️ 已备份 '{relative_path}' 到 '{backup_path}'")
        return backup_path
    except Exception as e:
        print(f"❌ 备份文件 '{file_path}' 时出错: {e}")
        return None

def generate_yaml_bundle(is_update=False):
    """【最终方案】将所有源 YAML 文件打包到一个中央 YAML 文件中"""
    action = "增量更新" if is_update else "生成/覆盖"
    print(f"\n--- {('5' if is_update else '1')}. {action}中央 YAML 配置文件 ---")

    if is_update and not os.path.exists(TARGET_YAML_BUNDLE_FILE):
        print("🤷 目标文件不存在，将执行首次生成操作。")
        generate_yaml_bundle(is_update=False)
        return

    yaml_files = find_yaml_files()
    if not yaml_files:
        print("🤷 未找到任何 YAML 文件，操作取消。")
        return

    if not is_update and os.path.exists(TARGET_YAML_BUNDLE_FILE):
        backup_file(TARGET_YAML_BUNDLE_FILE)

    existing_data = {}
    if is_update:
        try:
            with open(TARGET_YAML_BUNDLE_FILE, 'r', encoding='utf-8') as f:
                existing_data = yaml.safe_load(f) or {}
        except Exception as e:
            print(f"⚠️ 读取现有 YAML 文件失败({e})，将执行覆盖生成。")
            is_update = False

    new_config_data = {}
    print("🔄 正在处理 YAML 文件...")
    for file_path in yaml_files:
        relative_path = os.path.relpath(file_path, PROJECT_ROOT)
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            key_name = relative_path.replace(os.sep, '_').replace('.', '_')
            new_config_data[key_name] = {
                'path': relative_path,
                'content': content
            }
            print(f"  - 已处理: {relative_path}")
        except Exception as e:
            print(f"❌ 读取文件 '{relative_path}' 时出错: {e}")
    
    final_data = existing_data if is_update else {}
    for key, data in new_config_data.items():
        final_data[key] = data # 用新的数据覆盖或添加
    
    print(f"✅ 数据处理完成，准备写入中央配置文件...")

    try:
        with open(TARGET_YAML_BUNDLE_FILE, 'w', encoding='utf-8') as f:
            f.write(f"# Eridanus 配置文件捆绑包 (可直接编辑)\n")
            f.write(f"# 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            for key in sorted(final_data.keys()):
                data = final_data[key]
                f.write(f"{key}:\n")
                # 使用双引号确保路径即使有特殊字符也能正确解析
                f.write(f"  path: \"{data['path']}\"\n")
                # 使用字面量块 | 来保存内容，这是最关键的修复
                f.write(f"  content: |\n")
                # 将原始内容的每一行都进行缩进
                for line in data['content'].splitlines():
                    f.write(f"    {line}\n")
                f.write("\n") # 每个条目后加一个空行，更美观

        print(f"✨ 成功！所有配置已写入 '{TARGET_YAML_BUNDLE_FILE}'。你可以直接打开并编辑它了！")
    except Exception as e:
        print(f"❌ 写入 YAML 文件时出错: {e}")

def write_yaml_from_bundle():
    """【最终方案】从中央 YAML 文件写回到各个源 YAML 文件"""
    print(f"\n--- 2. 从中央 YAML 写回源文件 ---")
    if not os.path.exists(TARGET_YAML_BUNDLE_FILE):
        print(f"🤷 中央配置文件 '{TARGET_YAML_BUNDLE_FILE}' 不存在。请先使用选项 '1' 或 '5' 生成它。")
        return

    try:
        with open(TARGET_YAML_BUNDLE_FILE, 'r', encoding='utf-8') as f:
            config_data = yaml.safe_load(f)
    except Exception as e:
        print(f"❌ 读取中央 YAML 文件失败: {e}")
        return

    if not config_data:
        print("🤷 中央 YAML 文件为空，无可写内容。")
        return
        
    print("⚠️ 此操作将根据中央文件中的路径覆盖或创建对应的源 YAML 文件。")
    confirm = input("你确定要继续吗？(y/n): ")
    if confirm.lower() != 'y':
        print("🚫 操作已取消。")
        return

    print("🔄 正在写回源 YAML 文件...")
    count = 0
    for key, data in config_data.items():
        if 'path' not in data or 'content' not in data:
            print(f"  - ⚠️ 跳过无效条目: '{key}' (缺少 path 或 content)")
            continue
        
        file_path = os.path.join(PROJECT_ROOT, data['path'])
        original_content = data['content']

        parent_dir = os.path.dirname(file_path)
        ensure_dir_exists(parent_dir)

        if os.path.exists(file_path):
            backup_file(file_path)
        else:
            print(f"ℹ️ 文件 '{file_path}' 不存在，将创建新文件。")
        
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                # PyYAML 会处理好换行符，但内容末尾可能多一个换行，我们去掉
                f.write(original_content.strip() + '\n')
            print(f"  - ✅ 已更新: {file_path}")
            count += 1
        except Exception as e:
            print(f"  - ❌ 写入文件 '{file_path}' 时出错: {e}")
            
    print(f"\n✨ 操作完成，共更新/创建了 {count} 个文件。")


def backup_all_yaml_files():
    # ... 此函数无需修改 ...
    print("\n--- 3. 备份所有 YAML 配置文件 ---")
    yaml_files = find_yaml_files()
    if not yaml_files:
        print("🤷 未找到任何 YAML 文件，操作取消。")
        return
    ensure_dir_exists(BACKUP_DIR)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    specific_backup_dir = os.path.join(BACKUP_DIR, f"yaml_full_backup_{timestamp}")
    ensure_dir_exists(specific_backup_dir)
    print(f"🛡️ 将所有 YAML 文件备份到新目录: {specific_backup_dir}")
    count = 0
    for file_path in yaml_files:
        try:
            relative_path = os.path.relpath(file_path, RUN_DIR)
            backup_dest_path = os.path.join(specific_backup_dir, relative_path)
            ensure_dir_exists(os.path.dirname(backup_dest_path))
            shutil.copy(file_path, backup_dest_path)
            count += 1
        except Exception as e:
            print(f"❌ 备份文件 '{os.path.basename(file_path)}' 时出错: {e}")
    print(f"\n✅ 成功备份了 {count} 个 YAML 文件 (已保留目录结构)。")

def delete_backups():
    # ... 此函数无需修改 ...
    print("\n--- 4. 删除所有备份文件 ---")
    if not os.path.isdir(BACKUP_DIR):
        print("🤷 'backups' 目录不存在，无需删除。")
        return
    print("⚠️ " * 10)
    print("警告：此操作将永久删除 'backups/' 目录及其所有内容！")
    print("⚠️ " * 10)
    confirm = input("你确定要删除所有备份吗？请输入 'yes' 以确认: ")
    if confirm.lower() != 'yes':
        print("🚫 操作已取消。")
        return
    try:
        shutil.rmtree(BACKUP_DIR)
        print("🔥 'backups' 目录已成功删除。")
    except Exception as e:
        print(f"❌ 删除备份目录时出错: {e}")

def show_menu():
    print("\n" + "="*20 + " Eridanus 配置编辑器 v4.0 (YAML版) " + "="*20)
    print("      (使用中央 YAML 文件管理，稳定且可读)")
    print("="*70)
    print("请选择一个操作:")
    print("  1. [生成] 将所有 run/**/*.yaml 文件打包进一个中央 YAML 文件")
    print("  2. [写入] 从中央 YAML 文件写回到对应的源文件")
    print("  3. [备份] 备份当前所有的 run/**/*.yaml 文件")
    print("  4. [危险] 删除所有备份文件")
    print("  5. [更新] 增量更新中央 YAML 文件 (合并新旧)")
    print("  6. 退出")
    print("="*70)

def main():
    while True:
        show_menu()
        choice = input("请输入你的选择 (1-6): ")
        if choice == '1':
            generate_yaml_bundle(is_update=False)
        elif choice == '2':
            write_yaml_from_bundle()
        elif choice == '3':
            backup_all_yaml_files()
        elif choice == '4':
            delete_backups()
        elif choice == '5':
            generate_yaml_bundle(is_update=True)
        elif choice == '6':
            print("👋 感谢使用，再见！")
            break
        else:
            print("❌ 无效的输入，请输入 1 到 6 之间的数字。")
        
        input("\n按 Enter 键继续...")
        os.system('cls' if os.name == 'nt' else 'clear')

if __name__ == "__main__":
    main()