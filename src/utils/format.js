/**
 * Formata um número como moeda brasileira (BRL).
 *
 * @param {number} value - O valor a ser formatado.
 * @returns {string} O valor formatado como moeda brasileira (ex.: "R$ 1.234,56").
 */
export function formatSalary(value) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
}
