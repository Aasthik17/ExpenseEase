# server.py

from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import pickle
from werkzeug.utils import secure_filename
from receipt_model import ReceiptExtractor
import traceback

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = 'uploads'
MODEL_PATH = 'receipt_extractor.pkl'

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

with open(MODEL_PATH, 'rb') as f:
    model = pickle.load(f)

@app.route('/ocr', methods=['POST'])

@app.route('/ocr', methods=['POST'])
def process_image():
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400

    file = request.files['image']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    try:
        filename = secure_filename(file.filename)
        filepath = os.path.join('uploads', filename)
        file.save(filepath)

        print(f"[INFO] File saved to {filepath}")

        result = model.process(filepath)  # This is your ReceiptExtractor's method

        os.remove(filepath)
        return jsonify(result)

    except Exception as e:
        print("[ERROR] Exception occurred during processing:")
        traceback.print_exc()  # <-- This prints full error trace
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)