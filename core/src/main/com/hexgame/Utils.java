package com.hexgame;

import com.badlogic.gdx.graphics.Color;

import java.security.SecureRandom;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.Queue;
import java.util.Random;
import java.util.Set;

/**
 * Created by leheli on 2016.03.19..
 */
public class Utils {


    private static final Random RANDOM =new SecureRandom();

    public static <T extends Enum<?>> T randomEnum(Class<T> clazz) {
        int x = RANDOM.nextInt(clazz.getEnumConstants().length);
        return clazz.getEnumConstants()[x];
    }


   public static boolean isGameOver(GameObject current,GameObject end){
       return isGameOver(current, end, new HashSet<GameObject>(), new LinkedList<GameObject>());
   }


    private static boolean isGameOver(GameObject current,GameObject end ,Set<GameObject> traversed, Queue<GameObject> frontier){


        if(current.location.equals(end.location) ){
            return true;
        }

        Set<GameObject> availableNeighbours = current.getAvailableNeighbours();
        for (GameObject neighbour:availableNeighbours) {
            if(!traversed.contains(neighbour)){
                frontier.add(neighbour);
            }

        }

        if(frontier.isEmpty()){
            return false;
        }
        traversed.add(current);
        GameObject toVisit = frontier.remove();
        return isGameOver(toVisit,end,traversed,frontier);
    }


}
