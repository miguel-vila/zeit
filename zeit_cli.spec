# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for Zeit CLI.

Build with: uv run pyinstaller zeit_cli.spec
"""

block_cipher = None

a = Analysis(
    ['src/zeit/cli/main.py'],
    pathex=['src'],
    binaries=[],
    datas=[
        ('src/zeit/core/conf.yml', 'zeit/core'),
    ],
    hiddenimports=[
        # Typer and dependencies
        'typer',
        'click',
        'rich',
        'rich.console',
        'rich.prompt',
        'rich.markup',
        # Pydantic
        'pydantic',
        'pydantic_core',
        'pydantic.deprecated.decorator',
        # Ollama
        'ollama',
        'httpx',
        'httpcore',
        'h11',
        'anyio',
        'sniffio',
        # YAML
        'yaml',
        # Dotenv
        'dotenv',
        # Note: Opik excluded - has heavy deps (litellm), made optional in code
        # MSS for screenshots
        'mss',
        'mss.darwin',
        # Logging
        'logging.handlers',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude GUI dependencies - not needed for CLI
        'tkinter',
        'matplotlib',
        'scipy',
        'numpy',
        'PySide6',
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'shiboken6',
        # Test frameworks
        'pytest',
        'unittest',
        # IPython/Jupyter
        'IPython',
        'jupyter',
        'notebook',
        # Opik and its heavy dependencies (made optional in code)
        'opik',
        'litellm',
        'tiktoken',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='zeit',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # CLI app needs console
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file='entitlements.plist',
)
