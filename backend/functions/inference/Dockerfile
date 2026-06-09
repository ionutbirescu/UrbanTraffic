# Use AWS Lambda Python 3.12 base image
FROM public.ecr.aws/lambda/python:3.12

# Install system dependencies needed by librosa
RUN dnf install -y libsndfile && dnf clean all

# Install Python dependencies
# setuptools<81 still bundles pkg_resources, which librosa/numba import at runtime
RUN pip install --no-cache-dir \
    "setuptools<81" \
    tensorflow-cpu==2.18.0 \
    librosa==0.10.1 \
    numpy==1.26.4 \
    boto3

# Copy model files to /opt (loaded once at cold start)
COPY yamnet.tflite         /opt/yamnet.tflite
COPY yamnet_class_map.csv  /opt/yamnet_class_map.csv

# Copy Lambda handler
COPY app.py ${LAMBDA_TASK_ROOT}/app.py

# Lambda entrypoint
CMD ["app.lambda_handler"]