package com.hexgame;

import java.security.SecureRandom;
import java.util.Random;

/**
 * Created by leheli on 2016.03.19..
 */
public class Utils {


    private static final Random RANDOM =new SecureRandom();

    public static <T extends Enum<?>> T randomEnum(Class<T> clazz) {
        int x = RANDOM.nextInt(clazz.getEnumConstants().length);
        return clazz.getEnumConstants()[x];
    }




}
