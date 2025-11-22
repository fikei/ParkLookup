"""Scheduler for automated pipeline runs"""
import asyncio
import logging
import signal
import sys
from datetime import datetime, time
import schedule

from config import UPDATE_SCHEDULE, UPDATE_DAY, UPDATE_HOUR
from pipeline import run_pipeline

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Flag to control graceful shutdown
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global shutdown_requested
    logger.info(f"Received signal {signum}, initiating graceful shutdown...")
    shutdown_requested = True


def run_pipeline_sync():
    """Synchronous wrapper for the async pipeline"""
    logger.info(f"Scheduled pipeline run starting at {datetime.utcnow()}")
    try:
        success = asyncio.run(run_pipeline())
        if success:
            logger.info("Scheduled pipeline run completed successfully")
        else:
            logger.error("Scheduled pipeline run failed")
    except Exception as e:
        logger.exception(f"Scheduled pipeline run error: {e}")


def setup_schedule():
    """Configure the update schedule"""
    logger.info(f"Setting up {UPDATE_SCHEDULE} schedule")

    if UPDATE_SCHEDULE == "daily":
        schedule.every().day.at(f"{UPDATE_HOUR:02d}:00").do(run_pipeline_sync)
        logger.info(f"Pipeline scheduled to run daily at {UPDATE_HOUR:02d}:00 UTC")

    elif UPDATE_SCHEDULE == "weekly":
        day_func = getattr(schedule.every(), UPDATE_DAY.lower())
        day_func.at(f"{UPDATE_HOUR:02d}:00").do(run_pipeline_sync)
        logger.info(f"Pipeline scheduled to run every {UPDATE_DAY} at {UPDATE_HOUR:02d}:00 UTC")

    elif UPDATE_SCHEDULE == "monthly":
        # Run on the 1st of each month
        schedule.every().day.at(f"{UPDATE_HOUR:02d}:00").do(
            lambda: run_pipeline_sync() if datetime.utcnow().day == 1 else None
        )
        logger.info(f"Pipeline scheduled to run monthly on the 1st at {UPDATE_HOUR:02d}:00 UTC")

    else:
        logger.warning(f"Unknown schedule '{UPDATE_SCHEDULE}', defaulting to weekly")
        schedule.every().sunday.at(f"{UPDATE_HOUR:02d}:00").do(run_pipeline_sync)


def run_scheduler():
    """Run the scheduler loop"""
    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    setup_schedule()

    logger.info("Scheduler started. Press Ctrl+C to stop.")
    logger.info(f"Next run: {schedule.next_run()}")

    while not shutdown_requested:
        schedule.run_pending()
        # Sleep for 60 seconds between checks
        for _ in range(60):
            if shutdown_requested:
                break
            asyncio.run(asyncio.sleep(1))

    logger.info("Scheduler stopped.")


def run_once():
    """Run the pipeline once immediately"""
    logger.info("Running pipeline once...")
    run_pipeline_sync()


if __name__ == "__main__":
    if "--once" in sys.argv:
        run_once()
    else:
        run_scheduler()
