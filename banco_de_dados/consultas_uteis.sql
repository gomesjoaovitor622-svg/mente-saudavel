-- Consultas úteis para o banco do Mente Saudável (abra no DB Browser for SQLite, DBeaver etc.)

-- 1) Todos os usuários (sem mostrar a senha)
SELECT id, nome, email, perfil, registro, especialidade, criado_em FROM usuarios;

-- 2) Profissionais cadastrados
SELECT id, nome, registro AS crp, especialidade FROM usuarios WHERE perfil = 'profissional' ORDER BY nome;

-- 3) Sessões com o nome do paciente e do profissional (JOIN)
SELECT s.id, s.data_hora, s.modalidade, s.status,
       pac.nome AS paciente, pro.nome AS profissional
FROM sessoes s
JOIN usuarios pac ON pac.id = s.paciente_id
JOIN usuarios pro ON pro.id = s.profissional_id
ORDER BY s.data_hora;

-- 4) Agenda de hoje de um profissional (troque o id)
SELECT s.data_hora, s.modalidade, pac.nome AS paciente
FROM sessoes s JOIN usuarios pac ON pac.id = s.paciente_id
WHERE s.profissional_id = 1 AND s.status != 'cancelada'
  AND date(s.data_hora) = date('now', 'localtime')
ORDER BY s.data_hora;

-- 5) Quantas sessões concluídas cada paciente tem
SELECT pac.nome, COUNT(*) AS concluidas
FROM sessoes s JOIN usuarios pac ON pac.id = s.paciente_id
WHERE s.status = 'concluida' GROUP BY pac.id ORDER BY concluidas DESC;

-- 6) Pacientes ativos de cada profissional
SELECT pro.nome AS profissional, COUNT(DISTINCT s.paciente_id) AS pacientes_ativos
FROM sessoes s JOIN usuarios pro ON pro.id = s.profissional_id
WHERE s.status != 'cancelada' GROUP BY pro.id;

-- 7) Média de humor por usuário
SELECT u.nome, ROUND(AVG(h.nivel), 1) AS media_humor, COUNT(*) AS registros
FROM humor_registros h JOIN usuarios u ON u.id = h.usuario_id GROUP BY u.id;

-- 8) Quem está logado no app
SELECT u.nome, u.email FROM app_sessao a JOIN usuarios u ON u.id = a.usuario_id;
