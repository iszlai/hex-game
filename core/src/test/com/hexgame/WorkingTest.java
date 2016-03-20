package com.hexgame;
import org.junit.Ignore;
import org.junit.Test;

import java.util.HashSet;
import java.util.LinkedList;
import java.util.Objects;
import java.util.Set;

import static org.junit.Assert.assertTrue;

public class WorkingTest
{
    @Test
    public void thisAlwaysPasses()
    {
        assertTrue(true);
    }

    @Test
    @Ignore
    public void thisIsIgnored()
    {
        Set<Object> te=new HashSet<Object>();
        System.out.println(te.size());
        te.add("dsa");
        System.out.println(te.size());
        te.add(null);
        System.out.println(te.size());




    }
}
