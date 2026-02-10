const express = require('express');
const app = express();
const PORT = process.env.PORT || 3002;

app.get('/', (req, res) => res.json({ service: 'microservice', version: '1.0', status: 'healthy' }));
app.listen(PORT, '0.0.0.0', () => console.log(`Microservice on port ${PORT}`));
