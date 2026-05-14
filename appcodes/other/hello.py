#!/usr/bin/env python3
"""
シンプルな挨拶スクリプト
Simple greeting script that responds with "こんにちは" (Hello)
"""

def greet(name: str = "世界") -> str:
    """
    挨拶を返す関数
    
    Args:
        name: 挨拶する相手の名前（デフォルト: "世界" = World）
    
    Returns:
        挨拶メッセージ
    """
    return f"こんにちは、{name}！"


def main():
    """メイン関数"""
    print("=" * 40)
    print(greet())
    print(greet("Python"))
    print(greet("Azure"))
    print("=" * 40)
    print("\nこのスクリプトは簡単な挨拶を表示します。")
    print("This script displays a simple greeting.")


if __name__ == "__main__":
    main()
