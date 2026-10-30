// 最小 Rime 控制台，供 run.sh 测整句组词：rime_console <用户目录>，从标准输入读命令
//   keys <序列>      用 simulate_key_sequence 打字（支持 {Control+Shift+E} 这类写法）
//   opt <名> <0|1>   设置开关     get <名>  读开关
//   show             打印候选与注释      clear  清空输入
// 编译（Linux）：apt install librime-dev librime-plugin-lua librime-plugin-octagram
//               gcc -o rime_console rime_console.c -lrime
#include <rime_api.h>
#include <stdio.h>
#include <string.h>

static RimeApi *rime;

static void show(RimeSessionId s) {
  RIME_STRUCT(RimeCommit, commit);
  if (rime->get_commit(s, &commit)) { printf("COMMIT: %s\n", commit.text); rime->free_commit(&commit); }
  RIME_STRUCT(RimeContext, ctx);
  if (rime->get_context(s, &ctx)) {
    if (ctx.composition.length > 0) printf("PREEDIT: %s\n", ctx.composition.preedit);
    for (int i = 0; i < ctx.menu.num_candidates; i++)
      printf("  %d. %s  [%s]\n", i + 1, ctx.menu.candidates[i].text,
             ctx.menu.candidates[i].comment ? ctx.menu.candidates[i].comment : "");
    rime->free_context(&ctx);
  }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: %s <user_data_dir>\n", argv[0]); return 2; }
  rime = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[1];
  traits.log_dir = argv[1];
  traits.app_name = "rime.cn2en-bench";
  traits.min_log_level = 2;
  rime->setup(&traits);
  rime->initialize(NULL);
  if (rime->start_maintenance(True)) rime->join_maintenance_thread();
  RimeSessionId s = rime->create_session();
  if (!rime->select_schema(s, "rime_ice")) fprintf(stderr, "select_schema rime_ice failed\n");
  char line[4096];
  while (fgets(line, sizeof line, stdin)) {
    line[strcspn(line, "\n")] = 0;
    if (!strncmp(line, "keys ", 5)) { rime->simulate_key_sequence(s, line + 5); show(s); }
    else if (!strncmp(line, "opt ", 4)) { char n[256]; int v; if (sscanf(line + 4, "%255s %d", n, &v) == 2) rime->set_option(s, n, v); }
    else if (!strncmp(line, "get ", 4)) printf("%s=%d\n", line + 4, rime->get_option(s, line + 4));
    else if (!strcmp(line, "show")) show(s);
    else if (!strcmp(line, "clear")) rime->clear_composition(s);
    fflush(stdout);
  }
  rime->destroy_session(s);
  rime->finalize();
  return 0;
}
