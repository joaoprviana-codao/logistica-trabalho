require('dotenv').config()
const express = require('express')
const cors = require('cors')

const authRoutes = require('./routes/auth')
const pedidosRoutes = require('./routes/pedidos')
const produtosRoutes = require('./routes/produtos')
const entregadoresRoutes = require('./routes/entregadores')
const estoqueRoutes = require('./routes/estoque')
const pagamentosRoutes = require('./routes/pagamentos')
const relatoriosRoutes = require('./routes/relatorios')

const app = express()
const PORT = process.env.PORT || 3001

app.use(cors())
app.use(express.json())

app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'online', 
    message: ' Pizzatech API rodando!',
    timestamp: new Date().toISOString()
  })
})

app.use('/api/auth', authRoutes)
app.use('/api/pedidos', pedidosRoutes)
app.use('/api/produtos', produtosRoutes)
app.use('/api/entregadores', entregadoresRoutes)
app.use('/api/estoque', estoqueRoutes)
app.use('/api/pagamentos', pagamentosRoutes)
app.use('/api/relatorios', relatoriosRoutes)

app.use((err, req, res, next) => {
  console.error('Erro:', err)
  res.status(500).json({ 
    success: false, 
    error: 'Erro interno do servidor',
    details: err.message 
  })
})

app.listen(PORT, () => {
  console.log(` Servidor rodando em http://localhost:${PORT}`)
  console.log(` Rotas disponíveis:`)
  console.log(`   /api/health`)
  console.log(`   /api/auth`)
  console.log(`   /api/pedidos`)
  console.log(`   /api/produtos`)
  console.log(`   /api/entregadores`)
  console.log(`   /api/estoque`)
  console.log(`   /api/pagamentos`)
  console.log(`   /api/relatorios`)
})