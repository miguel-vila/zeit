class TrackingState:
    icon: str
    status_message: str
    can_toggle: bool

    def __init__(self, icon: str, status_message: str, can_toggle: bool):
        self.icon = icon
        self.status_message = status_message
        self.can_toggle = can_toggle

    @classmethod
    def not_within_work_hours(cls, status_message: str):
        return cls(icon="🌙", status_message=status_message, can_toggle=False)

    @classmethod
    def paused_manual(cls):
        return cls(icon="⏸️", status_message="Tracking paused (manual)", can_toggle=True)

    @classmethod
    def active(cls):
        return cls(icon="📊", status_message="Tracking active", can_toggle=True)
