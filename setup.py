from setuptools import setup, find_packages

setup(
    name="v2txt",
    version="0.1.0",
    description="Voice to Text - Start a voice conversation and get live transcriptions",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "SpeechRecognition>=3.10.0",
        "PyAudio>=0.2.14",
    ],
    entry_points={
        "console_scripts": [
            "v2txt=v2txt.cli:main",
        ],
    },
)
