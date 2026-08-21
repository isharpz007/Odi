from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root():
    return {"message": "OdiAI backend is running"}


@app.get("/hello")
def hello():
    return {"message": "kanye west is the goat!"
                       "kanye west is the goat!"
                       "kanye west is the goat!"
                       "kanye west is the goat!"}