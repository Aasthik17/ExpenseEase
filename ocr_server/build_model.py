# build_model.py

import pickle
from receipt_model import ReceiptExtractor

model = ReceiptExtractor()
with open("receipt_extractor.pkl", "wb") as f:
    pickle.dump(model, f)