# Roteiro de apresentação — minhas partes

**Tempo total: ~7 min** · Introdução e Arquitetura num ritmo tranquilo · foco na Conclusão.

---

## INTRODUÇÃO (~1min15)

**Slide 1 — Capa**
> Boa tarde a todos. O nosso projeto final é uma aplicação completa de dashboards e relatórios construída sobre a base de dados da Fórmula 1. A apresentação está dividida entre o grupo, e eu fico responsável por três partes: a introdução, a base de dados e a arquitetura, e o fechamento com as decisões de projeto e as dificuldades que enfrentamos.

**Slide 2 — Contexto e Objetivo**
> O objetivo do trabalho foi integrar, num único protótipo funcional, praticamente tudo que a gente viu ao longo da disciplina — funções, triggers, views, índices, controle de acesso e consultas mais complexas.
>
> A gente partiu da base relacional da Fórmula 1, que cobre o período de 1950 a 2025, e integrou com dados geográficos do mundo todo: países, cidades e aeroportos. Essa integração é o que dá um diferencial ao trabalho, porque permite cruzar o universo das corridas com informação geográfica — por exemplo, encontrar aeroportos próximos de uma cidade.
>
> E o ponto central é que a aplicação não é a mesma para todo mundo: ela atende três perfis de usuário — administrador, escuderia e piloto — e cada um enxerga só aquilo que faz sentido pro seu papel. O admin vê a base inteira; a escuderia e o piloto, apenas o próprio escopo.

---

## BASE DE DADOS E ARQUITETURA (~2min15)

**Slide 3 — Arquitetura e Tecnologias** *(~1min)*
> Falando da arquitetura: o banco é um PostgreSQL rodando em Docker, o que deixa o ambiente totalmente reproduzível — qualquer pessoa do grupo sobe a mesma base com um comando, sem depender de instalação local. A interface foi feita em Streamlit, que nos deixou montar as telas rapidamente em Python.
>
> Mas a decisão mais importante dessa parte é esta: todo o SQL é explícito, sem ORM. Ou seja, a lógica de negócio fica concentrada no banco, em funções e views, e o Python só chama o que já existe. Isso foi proposital — facilita a avaliação, porque dá pra ler exatamente o SQL que está sendo executado, e evita espalhar regra de negócio pela aplicação.
>
> [apontar o diagrama] No diagrama dá pra ver o fluxo completo: o usuário acessa pelo navegador, o Streamlit dispara o SQL explícito, e o PostgreSQL responde. E, do lado da carga, separamos em dois scripts — um carrega a base de dados e o outro a camada da aplicação.

**Slide 4 — Organização do projeto** *(~35s)*
> A organização do código segue essa mesma lógica de separar responsabilidades. Cada pasta tem um papel claro: uma para o banco, uma para a interface, uma para os dados, uma para os scripts de carga e uma para a documentação.
>
> E a carga tem uma ordem definida: primeiro a base, depois a camada da aplicação. Isso não é só estético — durante o desenvolvimento, sempre que a gente mexia numa função ou num índice, dava pra recarregar só a camada da aplicação, sem precisar reprocessar todos os dados de novo.

**Slide 5 — Modelo de Dados** *(~40s)*
> O modelo de dados tem dois grandes blocos. De um lado, as tabelas da Fórmula 1 — pilotos, escuderias, corridas, resultados, circuitos, classificações. Do outro, as tabelas geográficas — países, cidades, aeroportos, fusos horários.
>
> Um ponto que vale destacar é que essa base não é crua: ela já chegou aqui normalizada, deduplicada e com os vínculos ajustados no trabalho anterior, o T1. Então boa parte do esforço de limpeza — tratar nacionalidades, remover cidades duplicadas — já estava consolidado, e a gente construiu a aplicação em cima dessa base confiável.

> *[transição — se outra pessoa assume os Conceitos de BD e as Telas:]* A partir daqui, o(a) [nome] vai mostrar os conceitos de banco aplicados e as telas da aplicação funcionando.

---

## CONCLUSÃO (~3min15) — parte principal

**Slide 17 — Decisões de projeto e Dificuldades**

> Pra fechar, eu queria passar pelas principais decisões que tomamos. E a ideia aqui é mostrar que cada decisão não foi à toa — quase sempre ela nasceu de uma dificuldade concreta que apareceu no caminho.

- **Vínculo piloto–escuderia em tabela própria.** A gente criou uma tabela só pra representar essa relação. A dificuldade que motivou isso foi a seguinte: quando uma escuderia importa um piloto novo, esse piloto ainda não tem nenhum resultado em corrida — então não dava pra descobrir a qual escuderia ele pertence só olhando a tabela de resultados. A tabela própria resolveu esse caso e, de quebra, permite registrar que um piloto passou por várias escuderias ao longo da carreira.

- **Lógica no banco, e não no Python.** Como eu falei na arquitetura, toda a regra está em funções e triggers dentro do PostgreSQL, e a interface só chama. Reforço isso aqui porque foi uma decisão consciente: mantém o SQL explícito e auditável, e garante que a mesma regra valha independentemente de quem chama.

- **Carga separada entre base e aplicação.** Foi uma decisão bem prática, que veio da rotina de desenvolvimento. A gente ajustava função, view e índice o tempo todo, e recarregar a base inteira a cada teste era inviável. Separar a carga deixou esse ciclo muito mais rápido.

- **Senha em hash com pgcrypto.** As senhas nunca ficam em texto puro. Como os nossos usuários não são usuários reais do PostgreSQL, e sim registros numa tabela, a gente optou por guardar o hash da senha com a extensão pgcrypto — o que atende a exigência de proteger a senha sem precisar configurar autenticação no nível do servidor.

- **Sincronização por trigger.** Sempre que se cadastra um piloto ou uma escuderia, uma trigger cria automaticamente o usuário correspondente na tabela de usuários — e cancela a operação inteira se aquele login já existir, evitando inconsistência. Uma dificuldade específica aqui foi tratar a atualização: a gente teve que garantir que, ao atualizar um cadastro, a senha que o usuário porventura já tivesse trocado não fosse sobrescrita.

- **Views para centralizar os joins.** Vários relatórios precisavam da mesma junção de cinco ou seis tabelas. Em vez de repetir isso em cada função, a gente concentrou numa view e reaproveitou em todo lugar — o que deixou as funções muito mais enxutas e fáceis de manter.

- **Buscas sem acento e sem diferenciar maiúsculas.** Esse veio de um problema bem real de usabilidade: o usuário podia digitar "São Paulo", "sao paulo" ou "SAO PAULO", e todos tinham que casar com o que está armazenado. A gente resolveu normalizando com `unaccent` e `lower`, e usou a mesma ideia na busca de piloto por sobrenome.

> Além dessas, vale citar rapidamente outras dificuldades que apareceram: deduplicar as cidades e escolher qual seria a versão canônica; normalizar as nacionalidades para referenciar corretamente a tabela de países; calcular distância geográfica entre cidade e aeroporto, que a gente resolveu com a extensão `earthdistance`; e um detalhe curioso — os pontos da Fórmula 1 podem ser fracionados, existem corridas com meios-pontos, então tivemos que usar `NUMERIC` em vez de `INTEGER` pra não perder informação.

**Slide 18 — Obrigado**
> No fim, a gente conseguiu entregar uma aplicação que cobre os três perfis de usuário e exercita todos os conceitos da disciplina de forma integrada. Era isso. Muito obrigado, e ficamos abertos a perguntas.

---

### Dicas de tempo
- Se faltar tempo: na Conclusão, fale com calma os **4 primeiros** pontos e resuma os outros três numa frase só.
- Se sobrar tempo: detalhe mais o exemplo do relatório de aeroportos (cidade × distância) na Introdução.
- Frase-guia da Conclusão: *cada decisão nasceu de uma dificuldade concreta.*
- Use o diagrama (slide 3) e as telas só como apoio visual — não leia item por item.
