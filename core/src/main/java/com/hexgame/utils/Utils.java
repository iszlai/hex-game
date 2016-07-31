package com.hexgame.utils;

import com.hexgame.model.GameObject;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Queue;
import java.util.Random;
import java.util.Set;

/**
 * Created by leheli on 2016.03.19..
 */
public class Utils {


    private static final Random RANDOM = new SecureRandom();

    public static <T extends Enum<?>> T randomEnum(Class<T> clazz) {
        int x = RANDOM.nextInt(clazz.getEnumConstants().length);
        return clazz.getEnumConstants()[x];
    }


    private static Set<Integer> randomListNrOfElements(int to, int howMany) {
        Set<Integer> res = new HashSet<Integer>();

        while (res.size() < howMany) {
            res.add(1+RANDOM.nextInt(to));
        }
        return res;
    }


    private static List<GameObject> getSubset(Set<Integer> ids, List<GameObject> list) {
        List<GameObject> res = new ArrayList<GameObject>();
        for (Integer i : ids) {
            res.add(list.get(i));
        }

        return res;

    }

    public static List<GameObject> getElementsToBlock(List<GameObject> list,int howMany){
        Set<Integer> ids = randomListNrOfElements(list.size() - 1, howMany);
        return getSubset(ids,list);
    }




    public static boolean isGameOver(com.hexgame.model.GameObject current, com.hexgame.model.GameObject end) {
        return isGameOver(current, end, new HashSet<com.hexgame.model.GameObject>(), new LinkedList<com.hexgame.model.GameObject>());
    }


    private static boolean isGameOver(com.hexgame.model.GameObject current, com.hexgame.model.GameObject end, Set<com.hexgame.model.GameObject> traversed, Queue<com.hexgame.model.GameObject> frontier) {


        if (current.location.equals(end.location)) {
            return true;
        }

        Set<com.hexgame.model.GameObject> availableNeighbours = current.getAvailableNeighbours();
        for (com.hexgame.model.GameObject neighbour : availableNeighbours) {
            if (!traversed.contains(neighbour)) {
                frontier.add(neighbour);
            }

        }

        if (frontier.isEmpty()) {
            return false;
        }
        traversed.add(current);
        com.hexgame.model.GameObject toVisit = frontier.remove();
        return isGameOver(toVisit, end, traversed, frontier);
    }


}
