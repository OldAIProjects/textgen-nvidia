# --- BUILDER STAGE ---
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 as builder

# Install necessary packages for building
RUN apt-get update && \
    apt-get install --no-install-recommends -y git vim build-essential python3-dev python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Clone the GPTQ-for-LLaMa repository
RUN git clone https://github.com/oobabooga/GPTQ-for-LLaMa /build

WORKDIR /build

# Set up virtual environment and install necessary Python packages
RUN python3 -m venv /build/venv
RUN . /build/venv/bin/activate && \
    pip3 install --upgrade pip setuptools wheel && \
    pip3 install torch torchvision torchaudio && \
    pip3 install -r requirements.txt

# Build the wheel file for specific CUDA architectures
ARG TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX}"
RUN . /build/venv/bin/activate && \
    python3 setup_cuda.py bdist_wheel -d .

# --- MAIN APPLICATION STAGE ---
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

# Install necessary packages for the application
RUN apt-get update && \
    apt-get install --no-install-recommends -y python3-dev libportaudio2 libasound-dev git python3 python3-pip make g++ ninja-build && \
    rm -rf /var/lib/apt/lists/*

# Install virtualenv
RUN --mount=type=cache,target=/root/.cache/pip pip3 install virtualenv

# Clone the text-generation-webui repository
RUN git clone https://github.com/oobabooga/text-generation-webui /app

WORKDIR /app

# Set up virtual environment and upgrade basic Python tools
RUN virtualenv /app/venv
RUN . /app/venv/bin/activate && \
    pip3 install --upgrade pip setuptools wheel

# Copy the build artifacts from the builder stage and install the wheel file
COPY --from=builder /build /app/repositories/GPTQ-for-LLaMa
RUN . /app/venv/bin/activate && \
    pip3 install /app/repositories/GPTQ-for-LLaMa/*.whl

# Install extensions and their requirements
RUN --mount=type=cache,target=/root/.cache/pip . /app/venv/bin/activate && cd extensions/api && pip3 install -r requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip . /app/venv/bin/activate && cd extensions/elevenlabs_tts && pip3 install -r requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip . /app/venv/bin/activate && cd extensions/google_translate && pip3 install -r requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip . /app/venv/bin/activate && cd extensions/silero_tts && pip3 install -r requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip . /app/venv/bin/activate && cd extensions/whisper_stt && pip3 install -r requirements.txt

# Install the main application requirements
RUN . /app/venv/bin/activate && \
    pip3 install -r requirements.txt

# Copy necessary files
COPY . /app/

# Final settings and default command
ENV CLI_ARGS="--listen --api --chat"
CMD . /app/venv/bin/activate && python3 server.py ${CLI_ARGS}
