from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def root():
    return {"message": "OdiAI backend is running"}