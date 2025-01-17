FROM ubuntu:22.04 AS env_base
# Pre-reqs
RUN apt-get update && apt-get install --no-install-recommends -y \
    git vim build-essential python3-dev python3-venv python3-pip
# Instantiate venv and pre-activate
RUN pip3 install virtualenv
RUN virtualenv /venv
# Credit, Itamar Turner-Trauring: https://pythonspeed.com/articles/activate-virtualenv-dockerfile/
ENV VIRTUAL_ENV=/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN pip3 install --upgrade pip setuptools && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu && \
    pip3 install --upgrade requests beautifulsoup4 summarizer datetime PyPDF2 chromadb==0.3.18 lxml optuna pandas==2.0.3 posthog==2.4.2 sentence_transformers==2.2.2 spacy pytextrank num2words

FROM env_base AS app_base
# Copy and enable all scripts
COPY ./scripts /scripts
RUN chmod +x /scripts/*
### DEVELOPERS/ADVANCED USERS ###
# Clone oobabooga/text-generation-webui
RUN git clone https://github.com/JohnTheNerd/text-generation-webui /src
# Use script to check out specific version
ARG VERSION_TAG
ENV VERSION_TAG=${VERSION_TAG}
RUN . /scripts/checkout_src_version.sh
# To use local source: comment out the git clone command then set the build arg `LCL_SRC_DIR`
#ARG LCL_SRC_DIR="text-generation-webui"
#COPY ${LCL_SRC_DIR} /src
#################################
ENV LLAMA_CUBLAS=1
# Copy source to app
RUN cp -ar /src /app
# Install oobabooga/text-generation-webui
RUN --mount=type=cache,target=/root/.cache/pip pip3 install -r /app/requirements_cpu_only.txt && \
    pip uninstall -y llama_cpp_python_cuda llama-cpp-python && pip install llama-cpp-python --force-reinstall --upgrade
# Install extensions
RUN --mount=type=cache,target=/root/.cache/pip \
    chmod +x /scripts/build_extensions.sh && . /scripts/build_extensions.sh
# Clone default GPTQ
#RUN git clone https://github.com/oobabooga/GPTQ-for-LLaMa.git -b cuda /app/repositories/GPTQ-for-LLaMa
# Build and install default GPTQ ('quant_cuda')
#ARG TORCH_CUDA_ARCH_LIST="6.1;7.0;7.5;8.0;8.6+PTX"
#RUN cd /app/repositories/GPTQ-for-LLaMa/ && python3 setup_cuda.py install
# Install flash attention for exllamav2
#RUN pip install flash-attn --no-build-isolation

FROM ubuntu:22.04 AS base
# Runtime pre-reqs
RUN apt-get update && apt-get install --no-install-recommends -y \
    python3-venv python3-dev git
# Copy app and src
COPY --from=app_base /app /app
COPY --from=app_base /src /src
# Copy and activate venv
COPY --from=app_base /venv /venv
ENV VIRTUAL_ENV=/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
# Finalise app setup
WORKDIR /app
EXPOSE 7860
EXPOSE 5000
EXPOSE 5005
# Required for Python print statements to appear in logs
ENV PYTHONUNBUFFERED=1
# Force variant layers to sync cache by setting --build-arg BUILD_DATE
ARG BUILD_DATE
ENV BUILD_DATE=$BUILD_DATE
RUN echo "$BUILD_DATE" > /build_date.txt
ARG VERSION_TAG
ENV VERSION_TAG=$VERSION_TAG
RUN echo "$VERSION_TAG" > /version_tag.txt
# Copy and enable all scripts
COPY ./scripts /scripts
RUN chmod +x /scripts/*
# Run
ENTRYPOINT ["/scripts/docker-entrypoint.sh"]


# VARIANT BUILDS

FROM base AS llama-cpu
RUN echo "LLAMA-CPU" >> /variant.txt
RUN DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y git python3-dev build-essential python3-pip ffmpeg curl tzdata
RUN unset TORCH_CUDA_ARCH_LIST LLAMA_CUBLAS
#RUN pip uninstall -y llama_cpp_python_cuda llama-cpp-python && pip install llama-cpp-python --force-reinstall --upgrade
ENV EXTRA_LAUNCH_ARGS=""
CMD ["python3", "/app/server.py", "--cpu"]

