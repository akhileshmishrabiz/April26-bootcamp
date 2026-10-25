from pydantic import BaseModel, Field


class PlayerInput(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_-]+$")
    avatar: str = Field(default="🧑‍💻", min_length=1, max_length=12)


class AnswerInput(BaseModel):
    player_id: int = Field(gt=0)
    answer: str = Field(min_length=1, max_length=100)
