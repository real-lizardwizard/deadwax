from fastapi import APIRouter, Depends, HTTPException, Request
from src.logger import logger
from src.users import current_user, is_admin

router = APIRouter()


@router.get("/ping")
async def ping(request: Request, user: str = Depends(current_user)):
    try:
        slskd_client = request.app.state.slskd_client
        #? (2.0.4) its sentences said for the reader: slskd's address and key are an admin's to change
        ping_response = await slskd_client.ping(admin=is_admin(user))
        return ping_response
    except Exception as e:
        logger.error(f"Exception in /ping endpoint: {e}")
        raise HTTPException(status_code=500, detail=f"Error pinging slskd: {e}")
