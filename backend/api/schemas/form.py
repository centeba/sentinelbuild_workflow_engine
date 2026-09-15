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
    # A field named ``schema`` shadows pydantic's deprecated BaseModel.schema
    # method (typed as a callable); the field is valid and works at runtime.
    schema: FormSchema = Field(default_factory=FormSchema)  # type: ignore[assignment]
    is_active: bool = True


class FormUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=255)
    description: str | None = None
    schema: FormSchema | None = None  # type: ignore[assignment]
    is_active: bool | None = None


class FormResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    description: str | None
    schema: dict[str, Any]  # type: ignore[assignment]
    is_active: bool
    created_at: datetime
    updated_at: datetime
