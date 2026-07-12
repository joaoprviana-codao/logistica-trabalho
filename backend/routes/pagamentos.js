const express = require('express')
const router = express.Router()

router.get('/', (req, res) => {
  res.json({ message: 'Rota de pagamentos' })
})

module.exports = router