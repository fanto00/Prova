import pickle
from pathlib import Path


def save_master_db(db, path):
    """Save MASTER_DB (list of dicts) to a pickle file.

    Args:
        db: List of dictionaries containing damage records.
        path: File path where the pickle file will be saved.
    """
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "wb") as f:
        pickle.dump(db, f)


def load_master_db(path):
    """Load MASTER_DB from a pickle file.

    Args:
        path: File path to the pickle file.

    Returns:
        List of dictionaries containing damage records.
    """
    with open(path, "rb") as f:
        return pickle.load(f)
