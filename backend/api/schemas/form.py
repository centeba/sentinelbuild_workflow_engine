import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

FieldType = Literal["text", "textarea", "number", "email", "date", "select", "checkbox"]


class FormField(BaseModel):
    key: str = Field(min_length=1, max_length=100)
    label: str = Field(min_length=1, max_length=255)
    type: FieldType = "text"
    required: bool = False
    placeholder: str | None = None
    # For "select" fields.
    options: list[str] = Field(default_factory=list)


class FormSchema(BaseModel):
    fields: list[FormField] = Field(default_factory=list)


class FormCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    description: str | None = None
    schema: FormSchema = Field(default_factory=FormSchema)
    is_active: bool = True


class FormUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=255)
    description: str | None = None
    schema: FormSchema | None = None
    is_active: bool | None = None


class FormResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    description: str | None
    schema: dict[str, Any]
    is_active: bool
    created_at: datetime
    updated_at: datetime
