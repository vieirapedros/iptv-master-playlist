# Validação seletiva

O workflow executa `python3 run_validated_update.py`, que integra o filtro em uma cópia temporária do Bash, preservando fontes e HTTP. Executar somente o Bash original não aplica mídia.

Mídia: BR PT AR MX PE ES US GB IT FR JP CL CO UY PY BO EC VE DE DK NO SE NL.
WORLD e IPTV-ORG mantêm HTTP atual, com cache e exceções de domínio. IPTV-ORG não herda seleção por país. URL já gerenciada por mídia não escapa via HTTP.

ffprobe identifica fluxos; FFmpeg decodifica 20 segundos de vídeo e primeira faixa de áudio quando presente. Exige saída sem erro fatal, quadros e avanço de mídia. Vídeo sem áudio pode passar; rádio e páginas YouTube ficam fora dessas categorias de TV. Não detecta programação errada ou tela de erro transmitida como vídeo.

Falhas têm segunda tentativa; quatro URLs paralelas. Até 75 segundos de sondagem e outros 75 de decodificação por tentativa. Quarentena: fora da lista e reteste após sete dias na primeira execução disponível. Recuperação zera período contínuo. Após 30 dias, último reteste; nova falha descarta a URL. Outra URL é novo candidato.

Histórico versionado em validation_state/media.json: não apagar. URLs e cabeçalhos de aprovados/quarentena ficam públicos neste repositório; não usar credenciais privadas. Descartados e relatórios usam hashes. Aprovação não comprova procedência legal.

Autoteste local antes da rede. Estado inválido, falta de ferramentas ou exceção abortam. Pelo menos 20 testes com 95% de falhas interrompem publicação para revisão. ALLOW_MASS_FAILURE=1 libera somente essa guarda, sem aprovar reprovados. Guarda de playlist vazia permanece; proteção percentual considera somente grupos HTTP. Falha geral mantém master remoto anterior, com data antiga.

Artefato media-validation-report, retenção sete dias. README distingue mídia/HTTP na primeira execução publicada; contagens de URLs, não emissoras. Agenda segunda/sexta: retestes ocorrem na primeira execução após o prazo, não necessariamente no dia exato. Esta política prevalece sobre descrições antigas do README.
