# KipuBank Smart Contract

Um contrato bancário com controle de acesso baseado em roles, suporte multi-token, integração com oráculos Chainlink e sistema de conversão de decimais.

## Melhorias Implementadas

### 1. Sistema de Controle de Acesso
**Implementado:** OpenZeppelin's `AccessControl` com roles hierárquicos (ADMIN_ROLE e OPERATOR_ROLE).

**Por quê:** Proporciona gerenciamento seguro e granular de permissões seguindo best practices da indústria. Permite delegar responsabilidades operacionais sem comprometer a segurança administrativa.

### 2. Suporte Multi-Token
**Implementado:** Sistema unificado para ETH e tokens ERC-20 com contabilidade separada por ativo.

**Por quê:** Aumenta a versatilidade do contrato, permitindo lidar com múltiplos tipos de ativos. Usa `address(0)` para representar ETH nativamente, criando uma API consistente.

### 3. Integração com Oráculos Chainlink
**Implementado:** Price feeds para conversão em USD, validação de staleness e limites baseados em valor real.

**Por quê:** Fornece controles mais significativos baseados em valor real ao invés de quantidades voláteis. Permite limites de capacidade denominados em USD, mais úteis operacionalmente.

### 4. Sistema de Conversão de Decimais
**Implementado:** Normalização para 6 decimais (padrão USDC) com funções bidirecionais de conversão.

**Por quê:** Permite contabilidade precisa e comparação entre ativos com diferentes casas decimais (ETH 18, USDC 6, WBTC 8, etc.). Facilita agregação de portfólios multi-token.

### 5. Padrões de Segurança
**Implementado:** Checks-Effects-Interactions, Pausable, custom errors, e variáveis immutable/constant.

**Por quê:** Minimiza vetores de ataque (reentrancy), otimiza custos de gas (~50 gas economizado por revert com custom errors), e garante transparência com emissão abrangente de eventos.

## Instruções de Implantação

### Pré-requisitos
- Solidity ^0.8.30
- Foundry ou Hardhat
- ETH de testnet
- Endereços dos price feeds Chainlink

### 1. Compilação
```bash
forge build
```

### 2. Deploy do Contrato
```solidity
KipuBank bank = new KipuBank(
    1 ether,      // limite de saque inicial (ETH)
    100 ether     // capacidade inicial do banco (ETH)
);
```

### 3. Configurar Price Feed (Opcional mas Recomendado)
```solidity
bank.setPriceFeed(0x694AA1769357215DE4FAC081bf1f309aDC325306);
bank.setBankCapUSD(1_000_000_00000000);
bank.setUseUsdBankCap(true);
```

**Price Feeds Principais:**
- Sepolia ETH/USD: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
- Mainnet ETH/USD: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
- Lista completa: https://docs.chain.link/data-feeds/price-feeds/addresses

### 4. Adicionar Tokens Suportados
```solidity
bank.addSupportedToken(
    0x...,                    // endereço do token (ex: USDC)
    100_000 * 10**6,          // limite de saque
    10_000_000 * 10**6        // capacidade máxima
);

bank.setTokenPriceFeed(0x..., 0x...);
```

## Interação com o Contrato

### Usuários

**Depósitos:**
```solidity
bank.deposit{value: 1 ether}();

IERC20(token).approve(address(bank), amount);
bank.depositToken(token, amount);
```

**Saques:**
```solidity
bank.withdraw(0.5 ether);
bank.withdrawToken(token, amount);
```

**Consultas:**
```solidity
uint256 balance = bank.getTokenVaultBalance(user, address(0));
uint256 totalUSD = bank.getUserTotalValueInUSD(user);
```

### Administradores

**Controle:**
```solidity
bank.pause();
bank.unpause();
```

**Gestão de Tokens:**
```solidity
bank.updateTokenWithdrawalLimit(token, newLimit);
bank.updateTokenBankCap(token, newCap);
bank.removeSupportedToken(token);
```

**Emergência:**
```solidity
bank.emergencyWithdrawToken(token);
```

## Decisões de Design e Trade-offs

### 1. USD Bank Cap Opcional
**Decisão:** Cap em USD pode ser habilitado/desabilitado.

**Trade-off:** Adiciona complexidade (+1 flag booleana) mas oferece flexibilidade operacional. Permite operar sem oráculos se necessário.

### 2. Normalização para 6 Decimais
**Decisão:** Padronização em 6 decimais (USDC).

**Trade-off:** Perda de precisão para tokens >6 decimais, mas aceitável para aplicações financeiras. Balanceia precisão com custos de gas e simplicidade. Tokens com 18 decimais perdem ~12 dígitos menos significativos.

### 3. Auto-detecção de Decimais
**Decisão:** Detectar decimais via `IERC20Metadata`, fallback para 18, com override manual.

**Trade-off:** Reduz trabalho administrativo mas pode falhar com tokens não-padrão. Solução: função `setTokenDecimals()` permite correção manual quando necessário.

### 4. ETH como address(0)
**Decisão:** Representar ETH nativamente como `address(0)` no sistema unificado.

**Trade-off:** Padrão levemente não-convencional mas amplamente adotado. Permite API consistente entre ETH e ERC-20s, simplificando a lógica de negócio.

### 5. Whitelist de Tokens
**Decisão:** Admins devem aprovar cada token explicitamente.

**Trade-off:** Requer ação administrativa mas previne tokens maliciosos/incompatíveis. Evita contratos com lógica de transfer personalizada que podem quebrar o sistema.

### 6. Fee-on-Transfer Tokens
**Decisão:** Suportar tokens com taxas calculando `balanceAfter - balanceBefore`.

**Trade-off:** Adiciona 2 reads extras de storage (~2.1k gas) mas garante contabilidade correta. Essencial para tokens como USDT em certas redes.

### 7. Checks-Effects-Interactions
**Decisão:** Sempre atualizar estado antes de calls externos.

**Trade-off:** Pode requerer lógica mais verbosa mas previne reentrancy. Custo adicional mínimo de organização de código, benefício de segurança massivo.

## Segurança

**Padrões Implementados:**
- ✅ Checks-Effects-Interactions (previne reentrancy)
- ✅ Access Control (OpenZeppelin)
- ✅ Pausable (emergency stop)
- ✅ Validação de staleness de oráculos (max 1 hora)
- ✅ Custom errors (eficiência de gas)
- ✅ Whitelist de tokens

**Limitações Conhecidas:**
1. Remover token trava fundos dos usuários até reativação
2. Normalização pode perder precisão em tokens >6 decimais
3. Funcionalidades USD dependem de feeds Chainlink funcionais
4. Sem geração de yield/juros (versão futura)

## Estrutura do Projeto

```
src/
├── KipuBank.sol                          # Contrato principal (596 linhas)
└── interfaces/
    └── AggregatorV3Interface.sol         # Interface Chainlink

lib/openzeppelin-contracts/               # Dependências OpenZeppelin
foundry.toml                              # Configuração Foundry
remappings.txt                            # Mapeamento de imports
```

## Testes

```bash
forge test -vvv
```

## Otimizações de Gas

- Custom errors (~50 gas economizado por revert)
- `constant` para identificadores de role
- `immutable` para owner
- Nested mappings (O(1) lookups)
- Validações antecipadas (fail fast)

## License

MIT