"""Contratos (JSON Schema, draft 2020-12) das respostas validadas."""

DATA_ISO = {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}$"}

# ---- Serviço de referência -------------------------------------------------
ERROR = {
    "type": "object",
    "required": ["error"],
    "properties": {
        "error": {
            "type": "object",
            "required": ["code", "message"],
            "properties": {
                "code": {"type": "string", "minLength": 1},
                "message": {"type": "string", "minLength": 1},
                "details": {"type": "array"},
            },
        }
    },
}

HEALTH = {
    "type": "object",
    "required": ["status", "version", "uptime_s"],
    "properties": {
        "status": {"const": "ok"},
        "version": {"type": "string"},
        "uptime_s": {"type": "number", "minimum": 0},
    },
}

FERIADOS = {
    "type": "array",
    "minItems": 1,
    "items": {
        "type": "object",
        "required": ["date", "name", "type"],
        "properties": {"date": DATA_ISO, "name": {"type": "string", "minLength": 1}, "type": {"type": "string"}},
    },
}

CEP = {
    "type": "object",
    "required": ["cep", "logradouro", "bairro", "localidade", "uf"],
    "properties": {
        "cep": {"type": "string", "pattern": r"^\d{8}$"},
        "logradouro": {"type": "string"},
        "bairro": {"type": "string"},
        "localidade": {"type": "string"},
        "uf": {"type": "string", "minLength": 2, "maxLength": 2},
    },
}

VALIDAR_OK = {
    "type": "object",
    "required": ["valid", "sala"],
    "properties": {"valid": {"const": True}, "sala": {"type": "string", "pattern": r"^MenteSaudavel-[0-9a-f]{12}$"}},
}

# ---- APIs públicas reais (as que o app consome) ----------------------------
BRASILAPI_FERIADOS = {
    "type": "array",
    "minItems": 5,
    "items": {
        "type": "object",
        "required": ["date", "name"],
        "properties": {"date": DATA_ISO, "name": {"type": "string", "minLength": 1}},
    },
}

VIACEP_OK = {
    "type": "object",
    "required": ["cep", "logradouro", "bairro", "localidade", "uf"],
    "properties": {"cep": {"type": "string", "pattern": r"^\d{5}-\d{3}$"}, "uf": {"type": "string", "minLength": 2, "maxLength": 2}},
}

BRASILAPI_CEP_V2 = {
    "type": "object",
    "required": ["cep", "state", "city", "neighborhood", "street"],
    "properties": {"cep": {"type": "string"}, "state": {"type": "string", "minLength": 2, "maxLength": 2}, "city": {"type": "string"}},
}
