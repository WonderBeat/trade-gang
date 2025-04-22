#FROM ghcr.io/astral-sh/uv:alpine3.20
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
ENV UV_COMPILE_BYTECODE=1
RUN uv python install pypy@3.11

WORKDIR /app
ADD ./main.py /app
RUN uv sync --script "main.py" 

ADD . /app

CMD ["./main.py"]
