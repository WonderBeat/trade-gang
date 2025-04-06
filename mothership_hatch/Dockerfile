#FROM ghcr.io/astral-sh/uv:alpine3.20
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
ENV UV_COMPILE_BYTECODE=1
RUN uv python install 3.12
#RUN uv venv --python 3.12

ADD . /app

WORKDIR /app
RUN uv sync --script "hatch.py" 

CMD ["./hatch.py"]
