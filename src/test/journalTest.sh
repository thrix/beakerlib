# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted material 
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Authors:
#   Ales Zelinka <azelinka@redhat.com>
#   Petr Splichal <psplicha@redhat.com>

test_rlJournalStart(){
    [ -f $BEAKERLIB_JOURNAL ] && rm $BEAKERLIB_JOURNAL
    assertTrue "run id set" "[ -n '$BEAKERLIB_RUN' ]"
    assertTrue "journal started" "rlJournalStart"
    assertTrue "directory set & created" "[ -d $BEAKERLIB_DIR ]"
    assertTrue "journal file created" "[ -f $BEAKERLIB_JOURNAL ]"
    assertTrue "journal is well-formed XML" "xmllint $BEAKERLIB_JOURNAL >/dev/null"

    # existing journal is not overwritten
    rlLog "I am" &> /dev/null
    rlJournalStart
    assertTrue "existing journal not overwritten" \
            "grep 'I am' $BEAKERLIB_JOURNAL"

    # unless TESTID set a new random BeakerLib directory should be created
    local OLDTESTID=$TESTID
    local OLDDIR=$BEAKERLIB_DIR
    local OLDJOURNAL=$BEAKERLIB_JOURNAL
    unset TESTID
    rlJournalStart
    assertTrue "A new random dir created when no TESTID available" \
            "[ '$OLDDIR' != '$BEAKERLIB_DIR' -a -d $BEAKERLIB_DIR ]"
    assertTrue "A new journal created in random directory" \
            "[ '$OLDJOURNAL' != '$BEAKERLIB_JOURNAL' -a -f $BEAKERLIB_JOURNAL ]"
    rm -rf $BEAKERLIB_DIR
    export TESTID=$OLDTESTID
}

test_rlJournalPrint(){
    #add something to journal
    rlJournalStart
    rlPhaseStart FAIL       &> /dev/null
    rlAssert0 "failed" 1    &> /dev/null
    rlAssert0 "passed" 0    &> /dev/null
    rlPhaseEnd              &> /dev/null
    rlLog "loginek"         &> /dev/null
    assertTrue "rlJournalPrint dump is wellformed xml" \
            "rlJournalPrint |xmllint -"
    assertTrue "rlPrintJournal dump still works" \
            "rlPrintJournal | grep -v 'rlPrintJournal is obsoleted by rlJournalPrint' | xmllint -"
    assertTrue "rlPrintJournal emits obsolete warnings" \
            "rlPrintJournal | grep 'rlPrintJournal is obsoleted by rlJournalPrint' -q"
    rm -rf $BEAKERLIB_DIR
}

test_rlJournalPrintText(){
    #this fnc is used a lot in other function's tests
    #so here goes only some specific (regression?) tests

    #must not tracedump on an empty log message
    rlJournalStart          &> /dev/null
    #outside-of-phase log
    rlLog ""                &> /dev/null
    rlPhaseStart FAIL       &> /dev/null
    #inside-phase log
    rlLog ""                &> /dev/null
    assertFalse "no traceback during log creation" \
            "rlJournalPrintText 2>&1 | grep Traceback"
    rm -rf $BEAKERLIB_DIR

    #no traceback on non-ascii characters (bz471257)
    rlJournalStart
    rlPhaseStart FAIL               &> /dev/null
    rlLog "ščřžýáíéーれっどはっと"  &> /dev/null
    assertFalse "no traceback on non-ascii chars (unicode support)" \
            "rlJournalPrintText 2>&1 | grep Traceback"
    rm -rf $BEAKERLIB_DIR

    # no traceback on non-xml garbage
    rlJournalStart
    rlPhaseStart FAIL       &> /dev/null
    rlLog "$(echo $'\x00')"  &> /dev/null
    assertFalse "no traceback on non-xml characters [1]" \
            "rlJournalPrintText 2>&1 | grep Traceback"
    rlLog "$(echo $'\x0c')"  &> /dev/null
    assertFalse "no traceback on non-xml characters [2]" \
            "rlJournalPrintText 2>&1 | grep Traceback"
    rlLog "$(echo $'\x1F')"  &> /dev/null
    assertFalse "no traceback on non-xml characters [3]" \
            "rlJournalPrintText 2>&1 | grep Traceback"
    rm -rf $BEAKERLIB_DIR

    # multiline logs
    rlJournalStart
    rlLog "$(echo -e 'line1\nline2')" &> /dev/null
    rlJournalPrintText | grep -v "line2" | grep -q "LOG.*line1" &&
            rlJournalPrintText | grep -v "line1" | grep -q "LOG.*line2"
    assertTrue "multiline logs tagged on each line" "[ $? -eq 0 ]"
    rm -rf $BEAKERLIB_DIR

    # obsoleted rlCreateLogFromJournal still works
    rlJournalStart
    assertTrue "Checking the rlCreateLogFromJournal still works" \
            "rlCreateLogFromJournal | grep -q 'TEST PROTOCOL'"
    assertTrue "Obsoleted message for rlCreateLogFromJournal" \
            "rlCreateLogFromJournal | grep -q 'obsoleted by rlJournalPrintText'"
    rm -rf $BEAKERLIB_DIR
}

test_rlGetTestState(){
    #test this in developer mode to verify BZ#626953
    TESTID_BACKUP=$TESTID
    unset TESTID
    rlJournalStart
    assertRun "rlPhaseStart FAIL phase1"
    rlGetTestState ; assertTrue "rlGetTestState return 0 at the beginning of the test" "[ $? -eq 0 ]"
    rlGetPhaseState ; assertTrue "rlGetPhaseState return 0 at the beginning of the test" "[ $? -eq 0 ]"
    assertRun 'rlAssert0 "failing assert#1" 1' 1
    rlGetTestState ; assertTrue "rlGetTestState return 1 after assert failed" "[ $? -eq 1 ]"
    rlGetPhaseState ; assertTrue "rlGetPhaseState return 1 after assert failed" "[ $? -eq 1 ]"
    assertRun 'rlAssert0 "failing assert#2" 1' 1
    rlGetTestState ; assertTrue "rlGetTestState return 2 after assert failed" "[ $? -eq 2 ]"
    rlGetPhaseState ; assertTrue "rlGetPhaseState return 2 after assert failed" "[ $? -eq 2 ]"
    assertRun 'for i in $(seq 3 260) ; do rlAssert0 "failing assert#$i" 1; done' 1 "Creating 260 failed asserts"
    rlGetTestState ; assertTrue "rlGetTestState return 255 after more that 255 asserts failed" "[ $? -eq 255 ]"
    rlGetPhaseState ; assertTrue "rlGetPhaseState return 255 after more that 255 asserts failed" "[ $? -eq 255 ]"
    assertRun "rlPhaseEnd"

    assertRun "rlPhaseStart FAIL phase2"
    rlGetTestState ; assertTrue "rlGetTestState return non-zero in passing phase but failing test" "[ $? -ne 0 ]"
    rlGetPhaseState ; assertTrue "rlGetPhaseState return 0 in passing phase but failing test" "[ $? -eq 0 ]"
    assertRun "rlPhaseEnd"
    TESTID=$TESTID_BACKUP
}

test_rlGetPhaseState(){
    assertLog "Tests for this function are included in rlGetTestState since it is more or less the same"
}