import re
import cv2
import pytesseract
import os
from PIL import Image
from dateutil import parser
pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

CATEGORIES = ["Food", "Transportation", "Entertainment", "Shopping", "Bills", "Health", "Others"]

class ReceiptExtractor:
    def __init__(self, use_openai=True):
        self.use_openai = use_openai

    def preprocess_image(self, image_path):
        img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise ValueError(f"Image not loaded: {image_path}")
        img = cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        img = cv2.bilateralFilter(img, 9, 75, 75)
        _, thresh = cv2.threshold(img, 150, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        return Image.fromarray(thresh)

    def extract_date(self, text):
        patterns = [
            r'\b\d{2}/\d{2}/\d{4}\b', r'\b\d{2}-\d{2}-\d{4}\b',
            r'\b\d{4}-\d{2}-\d{2}\b', r'\b\d{1,2}\s+[A-Za-z]{3,}\s+\d{4}\b',
            r'\b[A-Za-z]{3,}\s+\d{1,2},\s+\d{4}\b'
        ]
        for pattern in patterns:
            match = re.search(pattern, text)
            if match:
                try:
                    return parser.parse(match.group(0)).strftime('%Y-%m-%d')
                except:
                    continue
        return None

    def extract_amount(self, text):
        text = text.lower().replace("tofal", "total").replace("totai", "total").replace("tota1", "total")
        amount_pattern = r"\d+\.\d{2}|\d+\,\d{2}|\d+"
        all_amounts = re.findall(amount_pattern, text.replace(" ", ""))
        all_amounts = [float(amt.replace(",", ".")) for amt in all_amounts if amt]

        # Look for specific total indicators
        lines = text.split('\n')
        for line in lines:
            if "total invoice value" in line.lower():
                amounts = re.findall(amount_pattern, line.replace(" ", ""))
                if amounts:
                    return float(amounts[-1].replace(",", "."))
            elif "total amount" in line.lower():
                amounts = re.findall(amount_pattern, line.replace(" ", ""))
                if amounts:
                    return float(amounts[-1].replace(",", "."))
            elif "total:" in line.lower() and "sub total" not in line.lower():
                amounts = re.findall(amount_pattern, line.replace(" ", ""))
                if amounts:
                    return float(amounts[-1].replace(",", "."))

        # Fallback to previous logic if specific indicators not found
        for line in reversed(lines):
            if "total" in line.lower() and "subtotal" not in line.lower():
                amounts = re.findall(amount_pattern, line.replace(" ", ""))
                if amounts:
                    return float(amounts[-1].replace(",", "."))

        if all_amounts:
            return max(all_amounts)
        return None

    def classify_category(self, text):
        text = text.lower()[:3000]
        keyword_mapping = {
            "Food": ["restaurant", "cafe", "food", "meal", "burger", "pizza", "domino"],
            "Transportation": ["taxi", "uber", "fuel", "gas", "metro", "toll"],
            "Entertainment": ["movie", "concert", "game", "netflix", "spotify"],
            "Shopping": ["store", "shop", "mall", "purchase", "buy", "walmart"],
            "Bills": ["bill", "electricity", "water", "internet", "rent"],
            "Health": ["hospital", "pharmacy", "medicine", "doctor", "clinic"]
        }
        for category, keywords in keyword_mapping.items():
            if any(keyword in text for keyword in keywords):
                return category
        return "Others"

    def process(self, image_path):
        img = self.preprocess_image(image_path)
        text = pytesseract.image_to_string(img)
        return {
            "date": self.extract_date(text),
            "amount": self.extract_amount(text),
            "category": self.classify_category(text)
        }