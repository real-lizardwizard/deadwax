from src.config import Config
from src.api.app import start
import uvicorn 
import asyncio
from src.logger import logger

#? seconds uvicorn waits for open requests at a stop before cancelling them - well inside docker's 10
GRACEFUL_SHUTDOWN_S = 5


def main():
    Config.check()
    
    api_app = start()

    config = uvicorn.Config(
        app=api_app,
        host="0.0.0.0",
        port=8080,
        log_level="debug",
        loop="asyncio",
        #? (2.0.0-player.65, the 2.0.0 release review) open streams - a song playing, the event log open - kept
        #? uvicorn waiting for them for ever, so `docker stop` SIGKILLed deadwax after its 10 s and the lifespan's
        #? teardown never ran. Past this, uvicorn cancels what is still open and then runs the teardown.
        timeout_graceful_shutdown=GRACEFUL_SHUTDOWN_S,
    )

    server = uvicorn.Server(config)
    
    try: 
        server.run()

    except (KeyboardInterrupt, asyncio.CancelledError):
        logger.info("Manually shutting down server due to KeyboardInterrupt...")

if __name__ == "__main__":
    main()