CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- agora as tabelas, acima foi uma extensão que eu utilizei
-- Abaixo vai ter a basicamente a tabela de entregadores
CREATE TABLE entregadores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    nome VARCHAR(100) NOT NULL,
    telefone VARCHAR(20),
    disponivel BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Beleza agora vamos para a categoria de PRODUTOS !

CREATE TABLE categorias (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome VARCHAR(50) NOT NULL,
    descricao TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tudo certo, agora vou criar outras diversas tabelas! 
-- Como o processo vai ser chato em criar as demais tabelas, irei apenas mostrar essa e as mais interessantes

CREATE TABLE produtos(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    categoria_id UUID REFERENCES categorias(id) ON DELETE SET NULL,
    nome VARCHAR(100) NOT NULL,
    descricao TEXT,
    imagem_url TEXT,
    preco_p DECIMAL(10,2),
    preco_m DECIMAL(10,2),
    preco_g DECIMAL(10,2),
    preco_gg DECIMAL(10,2),
    disponivel BOOLEAN DEFAULT TRUE,
    is_fixo BOOLEAN DEFAULT FALSE, -- tipo, se for TRUE vai ser = fixo do cardápio
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ingredientes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome VARCHAR(100) NOT NULL,
  unidade VARCHAR(10) NOT NULL, -- kg, g, l, ml, un
  quantidade_atual DECIMAL(10,3) DEFAULT 0,
  quantidade_minima DECIMAL(10,3) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE produto_ingredientes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  produto_id UUID REFERENCES produtos(id) ON DELETE CASCADE,
  ingrediente_id UUID REFERENCES ingredientes(id) ON DELETE CASCADE,
  quantidade DECIMAL(10,3) NOT NULL -- quanto usa por pizza
);

CREATE TABLE movimentacoes_estoque (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ingrediente_id UUID REFERENCES ingredientes(id) ON DELETE CASCADE,
  tipo VARCHAR(10) CHECK (tipo IN ('entrada', 'saida')),
  quantidade DECIMAL(10,3) NOT NULL,
  motivo TEXT,
  pedido_id UUID, -- será FK depois
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE pedidos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  numero INTEGER UNIQUE,
  cliente_nome VARCHAR(100) NOT NULL,
  cliente_telefone VARCHAR(20),
  endereco VARCHAR(200) NOT NULL,
  bairro VARCHAR(100),
  complemento VARCHAR(100),
  referencia VARCHAR(200),
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  status VARCHAR(20) DEFAULT 'recebido' 
    CHECK (status IN ('recebido', 'em_preparo', 'saiu_entrega', 'entregue', 'cancelado')),
  entregador_id UUID REFERENCES entregadores(id) ON DELETE SET NULL,
  subtotal DECIMAL(10,2) DEFAULT 0,
  taxa_entrega DECIMAL(10,2) DEFAULT 0,
  desconto DECIMAL(10,2) DEFAULT 0,
  total DECIMAL(10,2) DEFAULT 0,
  observacao TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE itens_pedido (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pedido_id UUID REFERENCES pedidos(id) ON DELETE CASCADE,
  produto_id UUID REFERENCES produtos(id) ON DELETE SET NULL,
  sabor VARCHAR(100) NOT NULL,
  tamanho VARCHAR(2) CHECK (tamanho IN ('P', 'M', 'G', 'GG')),
  quantidade INTEGER DEFAULT 1,
  valor_unitario DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE pagamentos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pedido_id UUID REFERENCES pedidos(id) ON DELETE CASCADE UNIQUE,
  forma VARCHAR(20) CHECK (forma IN ('dinheiro', 'cartao_credito', 'cartao_debito', 'pix')),
  valor_total DECIMAL(10,2) NOT NULL,
  valor_recebido DECIMAL(10,2),
  troco DECIMAL(10,2),
  status VARCHAR(20) DEFAULT 'pendente' CHECK (status IN ('pendente', 'pago', 'cancelado')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pedidos_status ON pedidos(status);
CREATE INDEX idx_pedidos_entregador ON pedidos(entregador_id);
CREATE INDEX idx_pedidos_created ON pedidos(created_at DESC);
CREATE INDEX idx_itens_pedido ON itens_pedido(pedido_id);
CREATE INDEX idx_movimentacoes_estoque ON movimentacoes_estoque(ingrediente_id, created_at DESC);
CREATE INDEX idx_pagamentos_pedido ON pagamentos(pedido_id);
CREATE INDEX idx_produtos_categoria ON produtos(categoria_id);


-- OPA GALERA ! voltei aqui depois de finalizar a parte repetitiva, e quis mostrar aqui
-- A parte de TRIGGERS e as funções do nosso SQL, como vamos mostrar o auto-incremento a seguir
CREATE OR REPLACE FUNCTION gerar_numero_pedido()
RETURNS TRIGGER AS $$
DECLARE
    ultimo INTEGER
BEGIN
    SELECT COALESCE(MAX(numero), 0) INTO ultimo FROM pedidos;
    NEW.NUMERO := ULTIMO +1;
    RETURN NEW:
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_numero_pedido
BEFORE INSERT ON pedidos
FOR EACH ROW EXECUTE FUNCTION gerar_numero_pedido();

-- Apenas isso, estou escrevendo as ações de código em letra maiuscula apenas para ficar mais didatico de aprender e mais facil de observar.
-- Aliás sempre adote essas práticas na hora de programar

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_pedidos_updated
BEFORE UPDATE ON pedidos
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trigger_entregadores_updated
BEFORE UPDATE ON entregadores
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trigger_produtos_updated
BEFORE UPDATE ON produtos
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trigger_ingredientes_updated
BEFORE UPDATE ON ingredientes
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE FUNCTION baixar_estoque_pedido()
RETURNS TRIGGER AS $$
DECLARE
  item RECORD;
  ing RECORD;
BEGIN
  -- Se o pedido mudou para "em_preparo", baixa os ingredientes
  IF NEW.status = 'em_preparo' AND OLD.status = 'recebido' THEN
    FOR item IN 
      SELECT ip.produto_id, ip.quantidade 
      FROM itens_pedido ip 
      WHERE ip.pedido_id = NEW.id
    LOOP
      FOR ing IN
        SELECT pi.ingrediente_id, pi.quantidade
        FROM produto_ingredientes pi
        WHERE pi.produto_id = item.produto_id
      LOOP
        -- Baixa a quantidade proporcional
        UPDATE ingredientes 
        SET quantidade_atual = quantidade_atual - (ing.quantidade * item.quantidade)
        WHERE id = ing.ingrediente_id;
        
        -- Registra a movimentação
        INSERT INTO movimentacoes_estoque (ingrediente_id, tipo, quantidade, motivo, pedido_id)
        VALUES (ing.ingrediente_id, 'saida', ing.quantidade * item.quantidade, 'Pedido #' || NEW.numero, NEW.id);
      END LOOP;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_baixa_estoque
AFTER UPDATE ON pedidos
FOR EACH ROW EXECUTE FUNCTION baixar_estoque_pedido();


-- Habilitar RLS, sempre bom né :)
ALTER TABLE entregadores ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE itens_pedido ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagamentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimentacoes_estoque ENABLE ROW LEVEL SECURITY;
ALTER TABLE produto_ingredientes ENABLE ROW LEVEL SECURITY;

-- Admin vê e gerencia tudo (a gente filtra pelo JWT depois)
CREATE POLICY "Admin acesso total entregadores" ON entregadores FOR ALL USING (true);
CREATE POLICY "Admin acesso total pedidos" ON pedidos FOR ALL USING (true);
CREATE POLICY "Admin acesso total itens" ON itens_pedido FOR ALL USING (true);
CREATE POLICY "Admin acesso total pagamentos" ON pagamentos FOR ALL USING (true);
CREATE POLICY "Admin acesso total produtos" ON produtos FOR ALL USING (true);
CREATE POLICY "Admin acesso total categorias" ON categorias FOR ALL USING (true);
CREATE POLICY "Admin acesso total ingredientes" ON ingredientes FOR ALL USING (true);
CREATE POLICY "Admin acesso total movimentacoes" ON movimentacoes_estoque FOR ALL USING (true);
CREATE POLICY "Admin acesso total prod_ing" ON produto_ingredientes FOR ALL USING (true);

-- Entregador vê so seus proprio pedidos (a gente ajusta na aplicação)
CREATE POLICY "Entregador ve seus pedidos" ON pedidos 
  FOR SELECT USING (
    auth.uid() IN (
      SELECT user_id FROM entregadores WHERE id = entregador_id
    )
  );


-- Categorias padrão
INSERT INTO categorias (nome, descricao) VALUES
('Tradicionais', 'Pizzas clássicas do cardápio'),
('Especiais', 'Pizzas especiais da casa'),
('Doces', 'Pizzas doces para sobremesa'),
('Bebidas', 'Refrigerantes, sucos e cervejas');

-- Produtos fixos (is_fixo = TRUE)
INSERT INTO produtos (categoria_id, nome, descricao, preco_p, preco_m, preco_g, preco_gg, is_fixo) 
SELECT c.id, 'Calabresa', 'Calabresa fatiada, cebola, mussarela e orégano', 35.00, 45.00, 55.00, 65.00, TRUE
FROM categorias c WHERE c.nome = 'Tradicionais';

INSERT INTO produtos (categoria_id, nome, descricao, preco_p, preco_m, preco_g, preco_gg, is_fixo) 
SELECT c.id, 'Margherita', 'Mussarela, tomate, manjericão fresco e orégano', 30.00, 40.00, 50.00, 60.00, TRUE
FROM categorias c WHERE c.nome = 'Tradicionais';

INSERT INTO produtos (categoria_id, nome, descricao, preco_p, preco_m, preco_g, preco_gg, is_fixo) 
SELECT c.id, 'Portuguesa', 'Presunto, ovo, cebola, ervilha, mussarela e orégano', 38.00, 48.00, 58.00, 68.00, TRUE
FROM categorias c WHERE c.nome = 'Tradicionais';

INSERT INTO produtos (categoria_id, nome, descricao, preco_p, preco_m, preco_g, preco_gg, is_fixo) 
SELECT c.id, 'Frango com Catupiry', 'Frango desfiado, catupiry, milho e mussarela', 40.00, 50.00, 60.00, 70.00, TRUE
FROM categorias c WHERE c.nome = 'Tradicionais';

INSERT INTO produtos (categoria_id, nome, descricao, preco_p, preco_m, preco_g, preco_gg, is_fixo) 
SELECT c.id, 'Quatro Queijos', 'Mussarela, provolone, parmesão, gorgonzola e orégano', 42.00, 52.00, 62.00, 72.00, TRUE
FROM categorias c WHERE c.nome = 'Especiais';

INSERT INTO ingredientes (nome, unidade, quantidade_atual, quantidade_minima) VALUES
('Mussarela', 'kg', 20.0, 5.0),
('Calabresa', 'kg', 10.0, 2.0),
('Cebola', 'kg', 8.0, 1.5),
('Tomate', 'kg', 10.0, 2.0),
('Manjericão', 'un', 50.0, 10.0),
('Presunto', 'kg', 8.0, 2.0),
('Ovo', 'un', 120.0, 30.0),
('Ervilha', 'kg', 5.0, 1.0),
('Frango desfiado', 'kg', 10.0, 2.0),
('Catupiry', 'kg', 8.0, 1.5),
('Milho', 'kg', 5.0, 1.0),
('Provolone', 'kg', 6.0, 1.5),
('Parmesão', 'kg', 5.0, 1.0),
('Gorgonzola', 'kg', 4.0, 1.0),
('Molho de tomate', 'kg', 15.0, 3.0),
('Massa de pizza', 'un', 200.0, 30.0),
('Orégano', 'kg', 3.0, 0.5);

-- "Ain por que tu programa com a tela minuscula" - Simples: as letras fica melhor pra ver
-- Enfim, por que diabos eu fiz um schema? Simples, apenas para meu professor ver tudo que eu fiz sobre o projeto e ter tudo anotadinho
-- agora vamos colocar essa bomba no supabase