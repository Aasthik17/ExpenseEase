const express = require('express');
const mysql = require('mysql2/promise'); // Changed to promise-based version
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Database connection
const db = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

// Test connection
db.getConnection()
  .then(connection => {
    console.log('Connected to MySQL database');
    connection.release();
  })
  .catch(err => {
    console.error('Database connection error:', err);
  });

// API Endpoints

// Signup
app.post('/api/signup', async (req, res) => {
  try {
    const { name, email, pin } = req.body;
    const [result] = await db.query(
      'INSERT INTO users (name, email, pin) VALUES (?, ?, ?)',
      [name, email, pin]
    );

    // Create default preferences
    try {
      await db.query(
        'INSERT INTO user_preferences (user_id) VALUES (?)',
        [result.insertId]
      );
    } catch (prefError) {
      console.error("Couldn't create preferences:", prefError);
    }

    res.json({ 
      user_id: result.insertId, 
      name, 
      email 
    });
  } catch (err) {
    console.error('Signup error:', err);
    res.status(400).json({ error: err.message });
  }
});

// Login
app.post('/api/login', async (req, res) => {
  try {
    const { email, pin } = req.body;
    const [rows] = await db.query(
      'SELECT * FROM users WHERE email = ? AND pin = ?',
      [email, pin]
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = rows[0];
    res.json({
      user_id: user.user_id,
      name: user.name,
      email: user.email
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get complete user data
app.get('/api/user-data/:userId', async (req, res) => {
  try {
    const userId = req.params.userId;
    
    // 1. Get user info
    const [userRows] = await db.query(
      'SELECT user_id, name, email FROM users WHERE user_id = ?',
      [userId]
    );

    if (userRows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    const user = userRows[0];

    // 2. Get preferences
    const [prefRows] = await db.query(
      'SELECT * FROM user_preferences WHERE user_id = ?',
      [userId]
    );
    const preferences = prefRows[0] || { theme_mode: 'system', currency_code: 'INR' };

    // 3. Get expenses
    const [expenses] = await db.query(
      'SELECT * FROM expenses WHERE user_id = ? ORDER BY date DESC',
      [userId]
    );

    res.json({
      user,
      preferences,
      expenses
    });
  } catch (err) {
    console.error('User data error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

// Add expense
// In server.js - Update the add expense endpoint
app.post('/api/expenses', async (req, res) => {
  console.log('Incoming expense data:', req.body);
  
  try {
    // Validate required fields
    if (!req.body.user_id || !req.body.title || !req.body.amount || !req.body.category) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Prepare the expense data
    const expenseData = {
      user_id: req.body.user_id,
      title: req.body.title,
      amount: parseFloat(req.body.amount),
      category: req.body.category,
      date: req.body.date || new Date().toISOString().split('T')[0], // Default to today
      notes: req.body.notes || null,
      source: req.body.source || null
    };

    console.log('Processed expense:', expenseData);

    // Insert into database
    const [result] = await db.query('INSERT INTO expenses SET ?', [expenseData]);
    
    // Return the complete created expense
    const [rows] = await db.query('SELECT * FROM expenses WHERE expense_id = ?', [result.insertId]);
    
    console.log('Successfully created expense:', rows[0]);
    res.json(rows[0]);
    
  } catch (err) {
    console.error('Error creating expense:', err);
    res.status(500).json({ error: 'Failed to create expense', details: err.message });
  }
});

// Delete expense
app.delete('/api/expenses/:expenseId', async (req, res) => {
  try {
    const expenseId = req.params.expenseId;
    const [result] = await db.query(
      'DELETE FROM expenses WHERE expense_id = ?',
      [expenseId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Expense not found' });
    }

    res.json({ message: 'Expense deleted successfully' });
  } catch (err) {
    console.error('Delete expense error:', err);
    res.status(500).json({ error: 'Failed to delete expense' });
  }
});

// Start server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});