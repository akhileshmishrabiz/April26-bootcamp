from sqlalchemy.orm import joinedload, selectinload


def ticket_list_options():
    from app.models.models import Ticket

    return (
        joinedload(Ticket.team),
        joinedload(Ticket.assignee),
        selectinload(Ticket.subtasks),
    )


def ticket_summary_options():
    from app.models.models import Ticket

    return (joinedload(Ticket.team),)


def incident_list_options():
    from app.models.models import Incident

    return (
        joinedload(Incident.team),
        joinedload(Incident.commander),
        joinedload(Incident.postmortem),
    )


def incident_summary_options():
    from app.models.models import Incident

    return (joinedload(Incident.team),)


def on_call_options():
    from app.models.models import OnCallSchedule

    return (
        joinedload(OnCallSchedule.user),
        joinedload(OnCallSchedule.team),
    )


def wheel_detail_options():
    from app.models.models import SpeakWheel, SpeakWheelName, SpeakWheelPick

    return (
        selectinload(SpeakWheel.names).selectinload(SpeakWheelName.picks),
        selectinload(SpeakWheel.picks).joinedload(SpeakWheelPick.name_entry),
    )
