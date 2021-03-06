// RUN: %llvmgxx %s -S -o -

// Test anonymous union with members of the same size.
int test1(float F) {
  union {
     float G;
     int i;
  };
  G = F;
  return i;
}

// test anonymous union with members of differing size.
int test2(short F) {
  volatile union {
     short G;
     int i;
  };
  G = F;
  return i;
}

// Make sure that normal unions work.  duh :)
volatile union {
  short S;
  int i;
} U;

int test3(short s) {
  U.S = s;
  return U.i;
}
