#!/usr/bin/env python3

from dotenv import load_dotenv
from zeit.cli.view_data import app

if __name__ == "__main__":
    load_dotenv()
    app()
