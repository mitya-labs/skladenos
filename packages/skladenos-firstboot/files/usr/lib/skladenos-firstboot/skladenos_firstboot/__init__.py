"""skladenOS: мастер первой загрузки. Бэкенды (bluetooth, wifi, account) не зависят от UI."""
import os

STATE_DIR = os.environ.get("SKLADENOS_STATE_DIR", "/var/lib/skladenos")
FLAG_NAME = "firstboot-done"
PENDING_NAME = "rename-pending"
