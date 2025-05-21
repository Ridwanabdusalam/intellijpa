import os
from fastapi import FastAPI, File, UploadFile, HTTPException
from deepgram import (
    DeepgramClient,
    DeepgramClientOptions,
    LiveTranscriptionEvents,
    LiveOptions,
    Microphone,
    DeepgramError, # Import DeepgramError for specific exception handling
)
from dotenv import load_dotenv
import logging # For more structured logging

load_dotenv()

# Setup basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# For local testing, replace with your actual Deepgram API Key
DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY", "fb7768611a8ea2a7c76d745ccc056966e5a1a93b")

app = FastAPI()

@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    logging.info(f"/transcribe endpoint called with file: {file.filename}")
    if not DEEPGRAM_API_KEY or DEEPGRAM_API_KEY == "fb7768611a8ea2a7c76d745ccc056966e5a1a93b":
        logging.error("Deepgram API key not configured.")
        raise HTTPException(status_code=500, detail="Deepgram API key not configured.")

    dg_connection = None  # Initialize to ensure it's defined for finally block
    transcription_result = ""
    deepgram_error_message = None # To store specific Deepgram errors

    try:
        # Initialize Deepgram client
        config = DeepgramClientOptions(
            verbose=0, 
            options={"keepalive": "true"}
        )
        deepgram: DeepgramClient = DeepgramClient(DEEPGRAM_API_KEY, config)

        # Create a live transcription connection
        dg_connection = deepgram.listen.live.v("1")

        # Define event handlers
        def on_open(self, open, **kwargs):
            logging.info(f"Deepgram connection opened: {open}")

        
        def on_message(self, result, **kwargs):
            nonlocal transcription_result
            sentence = result.channel.alternatives[0].transcript
            if len(sentence) > 0:
                transcription_result += (" " + sentence if transcription_result else sentence)
            logging.info(f"Deepgram interim transcript: {sentence}")


        def on_metadata(self, metadata, **kwargs):
            logging.info(f"Deepgram metadata: {metadata}")

        def on_speech_started(self, speech_started, **kwargs):
            logging.info(f"Deepgram speech started: {speech_started}")
            pass

        def on_utterance_end(self, utterance_end, **kwargs):
            logging.info(f"Deepgram utterance ended: {utterance_end}")
            pass 

        def on_close(self, close, **kwargs):
            logging.info(f"Deepgram connection closed: {close}")
            pass

        def on_error(self, error, **kwargs):
            nonlocal deepgram_error_message
            error_message = str(error.get('message', 'Unknown Deepgram error'))
            logging.error(f"Deepgram error: {error_message}")
            deepgram_error_message = error_message # Store the error message

        def on_unhandled(self, unhandled, **kwargs):
            logging.warning(f"Deepgram unhandled event: {unhandled}")
            pass

        dg_connection.on(LiveTranscriptionEvents.Open, on_open)
        dg_connection.on(LiveTranscriptionEvents.Transcript, on_message)
        dg_connection.on(LiveTranscriptionEvents.Metadata, on_metadata)
        dg_connection.on(LiveTranscriptionEvents.SpeechStarted, on_speech_started)
        dg_connection.on(LiveTranscriptionEvents.UtteranceEnd, on_utterance_end)
        dg_connection.on(LiveTranscriptionEvents.Close, on_close)
        dg_connection.on(LiveTranscriptionEvents.Error, on_error) # Make sure this is correctly assigned
        dg_connection.on(LiveTranscriptionEvents.Unhandled, on_unhandled)
        
        # Define live transcription options
        options: LiveOptions = LiveOptions(
            model="nova-2",
            language="en-US",
            # Apply encoding and sample rate if needed, otherwise defaults
            # encoding="linear16", # Example
            # sample_rate=16000,  # Example
            interim_results=True,
            utterance_end_ms="1000",
            vad_events=True,
        )

        # Start the connection
        logging.info("Attempting to start Deepgram connection.")
        if not await dg_connection.start(options): # dg_connection.start can be awaited
            logging.error("Failed to start Deepgram connection.")
            # The on_error handler should catch specific connection errors from Deepgram.
            # If start itself fails without an error event, this is a fallback.
            raise HTTPException(status_code=500, detail=deepgram_error_message or "Failed to connect to Deepgram (initiation phase).")

        logging.info("Deepgram connection started. Streaming audio data...")
        # Read the uploaded file in chunks and send to Deepgram
        chunk_size = 4096
        while True:
            data = await file.read(chunk_size)
            if not data:
                break
            dg_connection.send(data)
        
        logging.info("Finished sending audio data to Deepgram. Closing connection.")
        # Signal the end of the audio stream
        await dg_connection.finish() 

        # Wait for a short period for events to process, especially Close and final Transcript.
        import asyncio
        await asyncio.sleep(2) # This is a pragmatic delay. Robust solutions might use asyncio.Event.

        logging.info(f"Final transcription result: '{transcription_result}'")
        if deepgram_error_message:
            logging.error(f"Sending error response to Swift app: {deepgram_error_message}")
            return {"transcription": "", "error": f"Deepgram error: {deepgram_error_message}"}
        elif not transcription_result: # No transcription and no specific DG error
             logging.warning("No transcription received from Deepgram, and no specific Deepgram error was caught.")
             return {"transcription": "", "error": "No speech detected or empty audio."} # More specific
        
        logging.info("Sending successful transcription response to Swift app.")
        return {"transcription": transcription_result}

    except DeepgramError as e: # Specific Deepgram SDK errors
        logging.error(f"Deepgram SDK error: {e}")
        if dg_connection and dg_connection.is_connected():
            await dg_connection.finish()
        error_detail = f"Deepgram API error: {str(e)}"
        # Check for common error types if possible, e.g., auth by inspecting str(e) or specific exception types if available
        if "auth" in str(e).lower(): # Simplistic check
            error_detail = "Deepgram authentication error. Check API Key."
        raise HTTPException(status_code=500, detail=error_detail)
    except HTTPException as e:
        # Re-raise HTTPExceptions to be handled by FastAPI directly
        logging.error(f"HTTPException: {e.detail}")
        raise e
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}", exc_info=True) # Log full traceback
        if dg_connection and dg_connection.is_connected():
            await dg_connection.finish()
        raise HTTPException(status_code=500, detail=f"An unexpected server error occurred: {str(e)}")
    finally:
        # Ensure connection is closed if it was opened and is still connected
        if dg_connection and dg_connection.is_connected():
            logging.info("Ensuring Deepgram connection is closed in finally block.")
            await dg_connection.finish()

if __name__ == "__main__":
    import uvicorn
    # Note: Uvicorn is used for development. For production, consider a more robust ASGI server.
    uvicorn.run(app, host="0.0.0.0", port=8000)
