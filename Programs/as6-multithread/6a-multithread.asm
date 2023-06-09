; C:\IDE68K\UCOSII\6A-MULTITHREAD.C - Compiled by CC68K  Version 5.00 (c) 1991-2005  Peter J. Fondse
; /*
; * EXAMPLE_1.C
; *
; * This is a minimal program to verify multitasking.
; *
; */
; #include <stdio.h>
; #include <string.h>
; #include <ctype.h>
; #include <stdlib.h>
; #include <Bios.h>
; #include <ucos_ii.h>
; #define STACKSIZE 256
; /*
; ** Stacks for each task are allocated here in the application in this case = 256 bytes
; ** but you can change size if required
; */
; OS_STK Task1Stk[STACKSIZE];
; OS_STK Task2Stk[STACKSIZE];
; OS_STK Task3Stk[STACKSIZE];
; OS_STK Task4Stk[STACKSIZE];
; /* Prototypes for our tasks/threads*/
; void Task1(void *); /* (void *) means the child task expects no data from parent*/
; void Task2(void *);
; void Task3(void *);
; void Task4(void *);
; /*
; ** Our main application which has to
; ** 1) Initialise any peripherals on the board, e.g. RS232 for hyperterminal + LCD
; ** 2) Call OSInit() to initialise the OS
; ** 3) Create our application task/threads
; ** 4) Call OSStart()
; */
; void main(void)
; {
       section   code
       xdef      _main
_main:
       move.l    A2,-(A7)
       lea       _OSTaskCreate.L,A2
; // initialise board hardware by calling our routines from the BIOS.C source file
; Init_RS232();
       jsr       _Init_RS232
; Init_LCD();
       jsr       _Init_LCD
; /* display welcome message on LCD display */
; //Oline0('c');
; //Oline1("Micrium uC/OS-II RTOS");
; OSInit(); // call to initialise the OS
       jsr       _OSInit
; /*
; ** Now create the 4 child tasks and pass them no data.
; ** the smaller the numerical priority value, the higher the task priority
; */
; OSTaskCreate(Task1, OS_NULL, &Task1Stk[STACKSIZE], 12);
       pea       12
       lea       _Task1Stk.L,A0
       add.w     #512,A0
       move.l    A0,-(A7)
       clr.l     -(A7)
       pea       _Task1.L
       jsr       (A2)
       add.w     #16,A7
; OSTaskCreate(Task2, OS_NULL, &Task2Stk[STACKSIZE], 11); // highest priority task
       pea       11
       lea       _Task2Stk.L,A0
       add.w     #512,A0
       move.l    A0,-(A7)
       clr.l     -(A7)
       pea       _Task2.L
       jsr       (A2)
       add.w     #16,A7
; OSTaskCreate(Task3, OS_NULL, &Task3Stk[STACKSIZE], 13);
       pea       13
       lea       _Task3Stk.L,A0
       add.w     #512,A0
       move.l    A0,-(A7)
       clr.l     -(A7)
       pea       _Task3.L
       jsr       (A2)
       add.w     #16,A7
; OSTaskCreate(Task4, OS_NULL, &Task4Stk[STACKSIZE], 14); // lowest priority task
       pea       14
       lea       _Task4Stk.L,A0
       add.w     #512,A0
       move.l    A0,-(A7)
       clr.l     -(A7)
       pea       _Task4.L
       jsr       (A2)
       add.w     #16,A7
; OSStart(); // call to start the OS scheduler, (never returns from this function)
       jsr       _OSStart
       move.l    (A7)+,A2
       rts
; }
; /*
; ** IMPORTANT : Timer 1 interrupts must be started by the highest priority task
; ** that runs first which is Task2
; */
; void Task1(void *pdata)
; {
       xdef      _Task1
_Task1:
       link      A6,#0
       movem.l   D2/D3,-(A7)
; int LOWER_HEX_COUNT = 0;
       clr.l     D2
; int UPPER_HEX_COUNT = 0;
       clr.l     D3
; HEX_B = UPPER_HEX_COUNT;
       move.b    D3,4194322
; HEX_A = LOWER_HEX_COUNT;
       move.b    D2,4194320
; for (;;) {
Task1_1:
; if (LOWER_HEX_COUNT == 99) {
       cmp.l     #99,D2
       bne.s     Task1_4
; HEX_B = ++UPPER_HEX_COUNT;
       addq.l    #1,D3
       move.b    D3,4194322
; LOWER_HEX_COUNT = 0;
       clr.l     D2
; HEX_A = LOWER_HEX_COUNT;
       move.b    D2,4194320
       bra.s     Task1_5
Task1_4:
; } else {
; HEX_A = LOWER_HEX_COUNT++;
       move.l    D2,D0
       addq.l    #1,D2
       move.b    D0,4194320
Task1_5:
; }
; printf("This is Task #1\n");
       pea       @6a-mul~1_1.L
       jsr       _printf
       addq.w    #4,A7
; OSTimeDly(50);
       pea       50
       jsr       _OSTimeDly
       addq.w    #4,A7
       bra       Task1_1
; }
; }
; /*
; ** Task 2 below was created with the highest priority so it must start timer1
; ** so that it produces interrupts for the 100hz context switches
; */
; void Task2(void *pdata)
; {
       xdef      _Task2
_Task2:
       link      A6,#0
; // must start timer ticker here
; Timer1_Init() ; // this function is in BIOS.C and written by us to start timer
       jsr       _Timer1_Init
; for (;;) {
Task2_1:
; printf("....This is Task #2\n");
       pea       @6a-mul~1_2.L
       jsr       _printf
       addq.w    #4,A7
; OSTimeDly(10);
       pea       10
       jsr       _OSTimeDly
       addq.w    #4,A7
       bra       Task2_1
; }
; }
; void Task3(void *pdata)
; {
       xdef      _Task3
_Task3:
       link      A6,#-4
; int LED_COUNT = 0;
       clr.l     -4(A6)
; for (;;) {
Task3_1:
; printf("........This is Task #3\n");
       pea       @6a-mul~1_3.L
       jsr       _printf
       addq.w    #4,A7
; PortA = LED_COUNT++;
       move.l    -4(A6),D0
       addq.l    #1,-4(A6)
       move.b    D0,4194304
; OSTimeDly(10);
       pea       10
       jsr       _OSTimeDly
       addq.w    #4,A7
       bra       Task3_1
; }
; }
; void Task4(void *pdata)
; {
       xdef      _Task4
_Task4:
       link      A6,#0
; for (;;) {
Task4_1:
; printf("............This is Task #4\n");
       pea       @6a-mul~1_4.L
       jsr       _printf
       addq.w    #4,A7
; OSTimeDly(50);
       pea       50
       jsr       _OSTimeDly
       addq.w    #4,A7
       bra       Task4_1
; }
; }
       section   const
@6a-mul~1_1:
       dc.b      84,104,105,115,32,105,115,32,84,97,115,107,32
       dc.b      35,49,10,0
@6a-mul~1_2:
       dc.b      46,46,46,46,84,104,105,115,32,105,115,32,84
       dc.b      97,115,107,32,35,50,10,0
@6a-mul~1_3:
       dc.b      46,46,46,46,46,46,46,46,84,104,105,115,32,105
       dc.b      115,32,84,97,115,107,32,35,51,10,0
@6a-mul~1_4:
       dc.b      46,46,46,46,46,46,46,46,46,46,46,46,84,104,105
       dc.b      115,32,105,115,32,84,97,115,107,32,35,52,10
       dc.b      0
       section   bss
       xdef      _Task1Stk
_Task1Stk:
       ds.b      512
       xdef      _Task2Stk
_Task2Stk:
       ds.b      512
       xdef      _Task3Stk
_Task3Stk:
       ds.b      512
       xdef      _Task4Stk
_Task4Stk:
       ds.b      512
       xref      _Init_LCD
       xref      _Timer1_Init
       xref      _Init_RS232
       xref      _OSInit
       xref      _OSStart
       xref      _OSTaskCreate
       xref      _OSTimeDly
       xref      _printf
